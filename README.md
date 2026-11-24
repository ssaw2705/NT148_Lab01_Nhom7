# NT548 – Bài thực hành 01: Triển khai hạ tầng AWS bằng Terraform và CloudFormation

Mã nguồn triển khai tự động cùng một hạ tầng AWS bằng **hai công cụ** (Terraform và CloudFormation). Mỗi dịch vụ là một **module** riêng và có **test case** riêng.

## Kiến trúc

```
                         Internet
                            │
                    ┌───────┴────────┐
                    │ Internet GW    │
                    └───────┬────────┘
 VPC 10.0.0.0/16            │
 ┌──────────────────────────┼──────────────────────────────────┐
 │ Public Subnet 10.0.1.0/24│  (Public RT: 0.0.0.0/0 → IGW)    │
 │   ┌──────────────┐   ┌───┴─────────┐                        │
 │   │ Public EC2   │   │ NAT Gateway │ (Elastic IP)           │
 │   │ SG: SSH 22   │   └───┬─────────┘                        │
 │   │ từ IP/32     │       │                                  │
 │   └──────┬───────┘       │                                  │
 │          │ SSH           │                                  │
 │ Private Subnet 10.0.2.0/24 (Private RT: 0.0.0.0/0 → NAT)    │
 │   ┌──────▼───────┐                                          │
 │   │ Private EC2  │  SG: chỉ nhận SSH/ICMP từ Public EC2 SG  │
 │   └──────────────┘                                          │
 │ Default Security Group: chỉ cho phép traffic nội bộ trong SG│
 └─────────────────────────────────────────────────────────────┘
```

| Yêu cầu | Terraform | CloudFormation |
|---|---|---|
| VPC, Public/Private Subnet, Internet Gateway, Default SG | `terraform/modules/vpc` | `cloudformation/templates/vpc.yaml` |
| NAT Gateway (+ Elastic IP) | `terraform/modules/nat_gateway` | `cloudformation/templates/nat-gateway.yaml` |
| Public / Private Route Table | `terraform/modules/route_tables` | `cloudformation/templates/route-tables.yaml` |
| Public / Private EC2 Security Group | `terraform/modules/security_groups` | `cloudformation/templates/security-groups.yaml` |
| EC2 Public + Private | `terraform/modules/ec2` | `cloudformation/templates/ec2.yaml` |
| Ghép các module | `terraform/main.tf` | `cloudformation/main.yaml` (nested stacks) |

### Các biện pháp bảo mật cho EC2

- Public EC2 chỉ mở **port 22 cho đúng một IP** (`x.x.x.x/32`). Cả hai công cụ đều **từ chối** `0.0.0.0/0` (validation của Terraform, `AllowedPattern` của CloudFormation).
- Private EC2 **không có Public IP**, chỉ nhận SSH (22) và ping (ICMP) từ các máy thuộc Public EC2 SG (tham chiếu SG, không mở theo CIDR).
- Private EC2 ra Internet qua NAT Gateway, Internet không kết nối ngược vào được.
- Truy cập Private EC2 bằng **SSH ProxyJump** (`ssh -J`), nên private key **không bao giờ bị copy lên** Public EC2.
- Bắt buộc **IMDSv2**, **mã hoá** ổ đĩa root (EBS gp3).
- Default Security Group chỉ cho phép traffic giữa các thành viên của chính nó.

## Cấu trúc thư mục

```
lab1/
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf, versions.tf
│   ├── terraform.tfvars.example
│   ├── modules/{vpc,nat_gateway,route_tables,security_groups,ec2}/
│   └── tests/*.tftest.hcl          # unit test từng module (mock provider)
├── cloudformation/
│   ├── main.yaml                   # stack gốc (nested stacks)
│   ├── templates/*.yaml            # 5 module
│   ├── scripts/deploy.sh, destroy.sh
│   └── tests/test_templates.py     # unit test từng template
├── tests/
│   ├── test_deployed_infra.py      # test hạ tầng THẬT sau khi deploy (dùng chung 2 công cụ)
│   └── requirements.txt
└── .github/workflows/ci.yml        # tự chạy test offline mỗi lần push
```

## Chuẩn bị

1. Cài: [Terraform ≥ 1.7](https://developer.hashicorp.com/terraform/install), [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), Python ≥ 3.10, Git.
2. Cấu hình tài khoản AWS (IAM user có quyền EC2, CloudFormation, S3, SSM read):
   ```bash
   aws configure          # nhập Access Key, Secret Key, region ap-southeast-1
   aws sts get-caller-identity
   ```
3. Tạo cặp khoá SSH dùng cho lab:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/nt548-lab1 -N ""
   ```
4. Cài thư viện test:
   ```bash
   pip install -r tests/requirements.txt
   ```
5. Lấy IP public của bạn: `curl -s https://checkip.amazonaws.com`

> **Chi phí:** NAT Gateway tính tiền theo giờ (khoảng 0.045–0.059 USD/giờ tuỳ region). Làm xong nhớ **destroy**.

> **Windows:** chạy các lệnh trong Git Bash hoặc WSL. Đường dẫn `~/.ssh/...` vẫn dùng được trong Git Bash.

---

## Cách 1: Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Sửa allowed_ssh_cidr = "<IP của bạn>/32" trong terraform.tfvars

terraform init
terraform fmt -check -recursive
terraform validate
terraform test                  # unit test offline, không tạo tài nguyên, không tốn tiền
terraform plan -out tfplan
terraform apply tfplan
terraform output
```

SSH thử:

```bash
$(terraform output -raw ssh_public_command)    # vào Public EC2
$(terraform output -raw ssh_private_command)   # vào Private EC2 qua Public EC2
```

Chạy test trên hạ tầng thật (từ thư mục `lab1/`):

```bash
cd ..
IAC_TOOL=terraform AWS_REGION=ap-southeast-1 SSH_KEY_PATH=~/.ssh/nt548-lab1 \
  pytest -v tests/test_deployed_infra.py
```

Xoá tài nguyên:

```bash
cd terraform && terraform destroy
```

---

## Cách 2: CloudFormation

CloudFormation cần Key Pair có sẵn trên AWS, nên import public key vừa tạo:

```bash
aws ec2 import-key-pair --region ap-southeast-1 --key-name nt548-lab1-key \
  --public-key-material fileb://~/.ssh/nt548-lab1.pub
```

> Nếu bạn đã chạy Terraform trước đó và **chưa destroy**, key `nt548-lab1-key` đã tồn tại (do Terraform tạo). Khi đó bỏ qua bước import, hoặc dùng tên khác qua biến `KEY_NAME`.

Kiểm tra và test offline:

```bash
cd cloudformation
cfn-lint                       # kiểm tra cú pháp + best practice
pytest -v tests                # unit test từng template
```

Triển khai (script tự tạo S3 bucket chứa template con, đóng gói nested stacks rồi deploy; IP SSH được lấy tự động):

```bash
AWS_REGION=ap-southeast-1 KEY_NAME=nt548-lab1-key ./scripts/deploy.sh
# Hoặc chỉ định IP: ALLOWED_SSH_CIDR=203.0.113.10/32 ./scripts/deploy.sh
```

SSH thử (lấy IP từ Outputs mà script in ra):

```bash
ssh -i ~/.ssh/nt548-lab1 ec2-user@<PublicInstancePublicIp>
ssh -i ~/.ssh/nt548-lab1 -J ec2-user@<PublicInstancePublicIp> ec2-user@<PrivateInstancePrivateIp>
```

Chạy test trên hạ tầng thật (từ thư mục `lab1/`):

```bash
cd ..
IAC_TOOL=cloudformation STACK_NAME=nt548-lab1-cfn AWS_REGION=ap-southeast-1 \
  SSH_KEY_PATH=~/.ssh/nt548-lab1 pytest -v tests/test_deployed_infra.py
```

Xoá tài nguyên:

```bash
./cloudformation/scripts/destroy.sh
```

---

## Danh sách test case

### Unit test (offline, không tốn tiền)

| Dịch vụ | Terraform (`terraform test`) | CloudFormation (`pytest cloudformation/tests`) |
|---|---|---|
| VPC | CIDR đúng, bật DNS; Public Subnet tự gán Public IP; Private Subnet không gán; IGW gắn vào VPC; Default SG chỉ cho phép traffic nội bộ trong SG; CIDR sai bị từ chối | Tương tự |
| NAT Gateway | Nằm trong Public Subnet, dùng Elastic IP, loại public | Tương tự |
| Route Tables | Public RT `0.0.0.0/0 → IGW` gắn Public Subnet; Private RT `0.0.0.0/0 → NAT` gắn Private Subnet, không đi thẳng ra IGW | Tương tự |
| Security Groups | Public SG chỉ mở 22 từ IP chỉ định; Private SG chỉ nhận từ Public SG; mở `0.0.0.0/0` bị từ chối | Tương tự + tham số bắt buộc `/32` |
| EC2 | Public có Public IP, Private không có; IMDSv2; ổ đĩa mã hoá; đúng subnet/SG | Tương tự |
| Toàn stack | Các module nối đúng với nhau (`integration.tftest.hcl`) | Đủ 5 nested stack, truyền đúng output giữa các stack |

### Test sau triển khai (`tests/test_deployed_infra.py`, gọi AWS API thật)

| Dịch vụ | Kiểm tra |
|---|---|
| VPC | VPC `available`, bật DNS; subnet đúng VPC và đúng cờ Public IP; IGW `attached`; Default SG không mở CIDR nào |
| NAT Gateway | `available`, nằm trong Public Subnet, có Public IP |
| Route Tables | Route mặc định của Public RT trỏ IGW, của Private RT trỏ NAT; association đúng subnet |
| Security Groups | Public SG chỉ có 1 rule tcp/22 từ đúng 1 IP `/32`; Private SG chỉ nhận từ Public SG |
| EC2 | Hai instance `running`, đúng subnet/SG, Public có IP công khai, Private không có, IMDSv2 bắt buộc |
| Kết nối (khi đặt `SSH_KEY_PATH`) | SSH từ máy bạn vào Public EC2 được; SSH vào Private EC2 qua Public EC2 được; Private EC2 gọi ra Internet và IP nhìn thấy đúng bằng Elastic IP của NAT |

## Tuỳ chỉnh

- Đổi region, CIDR, loại instance: sửa `terraform/terraform.tfvars` hoặc tham số trong `cloudformation/main.yaml` (`--parameter-overrides`).
- Mở thêm port cho Private EC2 (Terraform): biến `private_ingress_ports` của module `security_groups`, ví dụ `[22, 80]`.
- AMI mặc định là Amazon Linux 2023 mới nhất, lấy qua SSM Parameter Store nên không bị cũ.

## Kết quả

Đã triển khai thật trên AWS (region `ap-southeast-1`, Amazon Linux 2023, `t3.micro`) bằng cả hai công cụ, chạy test rồi xoá toàn bộ tài nguyên.

| Kiểm tra | Terraform | CloudFormation |
|---|---|---|
| Triển khai | `Apply complete! Resources: 23 added` | Stack gốc + 6 nested stack `CREATE_COMPLETE` (module EC2 dùng lại cho Public và Private) |
| Test hạ tầng thật (`tests/test_deployed_infra.py`) | **18/18 passed** | **18/18 passed** |
| SSH vào Public EC2 từ Internet (chỉ từ IP `/32` được cho phép) | ✅ | ✅ |
| SSH vào Private EC2 qua Public EC2 (ProxyJump) | ✅ | ✅ |
| Private EC2 không có Public IP | ✅ | ✅ |
| Private EC2 ra Internet qua NAT (IP nhìn thấy = Elastic IP của NAT) | ✅ | ✅ |
| Xoá tài nguyên (`terraform destroy` / `destroy.sh`) | ✅ | ✅ |

Số test theo từng dịch vụ (giống nhau cho cả hai công cụ):

| Dịch vụ | Số test | Nội dung |
|---|---|---|
| VPC | 6 | VPC available, bật DNS; Public/Private Subnet; Internet Gateway attached; Default SG chỉ cho phép traffic nội bộ |
| NAT Gateway | 1 | Available, nằm trong Public Subnet, có Elastic IP |
| Route Tables | 2 | Public RT → IGW, Private RT → NAT, gắn đúng subnet |
| Security Groups | 2 | Public SG chỉ SSH 22 từ 1 IP `/32`; Private SG chỉ nhận từ Public SG |
| EC2 | 4 | Public có Public IP, Private không có; IMDSv2 bắt buộc trên cả hai |
| Kết nối thực tế | 3 | SSH Public, SSH Private qua Public, Private ra Internet qua NAT |
