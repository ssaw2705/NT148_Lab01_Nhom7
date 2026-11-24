"""Test kiem tra ha tang THAT tren AWS sau khi trien khai (dung chung cho
Terraform va CloudFormation). Moi dich vu co nhom test rieng.

Chay:
  IAC_TOOL=terraform      pytest -v tests/test_deployed_infra.py
  IAC_TOOL=cloudformation pytest -v tests/test_deployed_infra.py

Bien moi truong:
  IAC_TOOL      terraform | cloudformation (mac dinh terraform)
  STACK_NAME    ten stack CloudFormation (mac dinh nt548-lab1-cfn)
  AWS_REGION    region (mac dinh ap-southeast-1)
  SSH_KEY_PATH  private key; neu co thi chay them test ket noi SSH/NAT that
  OUTPUTS_JSON  (tuy chon) file JSON chua san cac ID, bo qua viec doc output
"""
import ipaddress
import json
import os
import subprocess
from pathlib import Path

import boto3
import pytest

LAB_ROOT = Path(__file__).resolve().parents[1]
REGION = os.environ.get("AWS_REGION", "ap-southeast-1")
TOOL = os.environ.get("IAC_TOOL", "terraform")

# Ten chuan hoa -> (ten output Terraform, ten output CloudFormation)
OUTPUT_MAP = {
    "vpc_id": ("vpc_id", "VpcId"),
    "public_subnet_id": ("public_subnet_id", "PublicSubnetId"),
    "private_subnet_id": ("private_subnet_id", "PrivateSubnetId"),
    "igw_id": ("internet_gateway_id", "InternetGatewayId"),
    "default_sg_id": ("default_security_group_id", "DefaultSecurityGroupId"),
    "nat_id": ("nat_gateway_id", "NatGatewayId"),
    "public_rt_id": ("public_route_table_id", "PublicRouteTableId"),
    "private_rt_id": ("private_route_table_id", "PrivateRouteTableId"),
    "public_sg_id": ("public_sg_id", "PublicSecurityGroupId"),
    "private_sg_id": ("private_sg_id", "PrivateSecurityGroupId"),
    "public_instance_id": ("public_instance_id", "PublicInstanceId"),
    "private_instance_id": ("private_instance_id", "PrivateInstanceId"),
}


def _load_outputs():
    if os.environ.get("OUTPUTS_JSON"):
        return json.loads(Path(os.environ["OUTPUTS_JSON"]).read_text())
    if TOOL == "terraform":
        raw = json.loads(subprocess.check_output(
            ["terraform", "output", "-json"], cwd=LAB_ROOT / "terraform"))
        return {k: raw[tf]["value"] for k, (tf, _) in OUTPUT_MAP.items()}
    stack = os.environ.get("STACK_NAME", "nt548-lab1-cfn")
    cfn = boto3.client("cloudformation", region_name=REGION)
    outs = cfn.describe_stacks(StackName=stack)["Stacks"][0]["Outputs"]
    raw = {o["OutputKey"]: o["OutputValue"] for o in outs}
    return {k: raw[cf] for k, (_, cf) in OUTPUT_MAP.items()}


@pytest.fixture(scope="session")
def out():
    return _load_outputs()


@pytest.fixture(scope="session")
def ec2():
    return boto3.client("ec2", region_name=REGION)


def _sg(ec2, sg_id):
    return ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]


def _instance(ec2, instance_id):
    return ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0]["Instances"][0]


def _instance_sgs(i):
    groups = i.get("SecurityGroups") or i["NetworkInterfaces"][0]["Groups"]
    return sorted(g["GroupId"] for g in groups)


def _default_route(rt):
    return next(r for r in rt["Routes"] if r.get("DestinationCidrBlock") == "0.0.0.0/0")


# ======================= 1. VPC =======================
class TestVpc:
    def test_vpc_available(self, ec2, out):
        vpc = ec2.describe_vpcs(VpcIds=[out["vpc_id"]])["Vpcs"][0]
        assert vpc["State"] == "available"

    def test_vpc_dns_enabled(self, ec2, out):
        for attr, key in [("enableDnsSupport", "EnableDnsSupport"),
                          ("enableDnsHostnames", "EnableDnsHostnames")]:
            res = ec2.describe_vpc_attribute(VpcId=out["vpc_id"], Attribute=attr)
            assert res[key]["Value"] is True

    def test_public_subnet(self, ec2, out):
        s = ec2.describe_subnets(SubnetIds=[out["public_subnet_id"]])["Subnets"][0]
        assert s["VpcId"] == out["vpc_id"]
        assert s["MapPublicIpOnLaunch"] is True

    def test_private_subnet(self, ec2, out):
        s = ec2.describe_subnets(SubnetIds=[out["private_subnet_id"]])["Subnets"][0]
        assert s["VpcId"] == out["vpc_id"]
        assert s["MapPublicIpOnLaunch"] is False

    def test_internet_gateway_attached(self, ec2, out):
        igw = ec2.describe_internet_gateways(InternetGatewayIds=[out["igw_id"]])["InternetGateways"][0]
        assert {"VpcId": out["vpc_id"], "State": "available"} in igw["Attachments"]

    def test_default_security_group_only_self(self, ec2, out):
        sg = _sg(ec2, out["default_sg_id"])
        assert sg["VpcId"] == out["vpc_id"]
        for perm in sg["IpPermissions"]:
            assert not perm.get("IpRanges"), "Default SG khong duoc mo theo CIDR"
            assert [p["GroupId"] for p in perm["UserIdGroupPairs"]] == [sg["GroupId"]]


# ======================= 2. NAT Gateway =======================
class TestNatGateway:
    def test_nat_available_in_public_subnet(self, ec2, out):
        nat = ec2.describe_nat_gateways(NatGatewayIds=[out["nat_id"]])["NatGateways"][0]
        assert nat["State"] == "available"
        assert nat["SubnetId"] == out["public_subnet_id"]
        assert nat["NatGatewayAddresses"][0].get("PublicIp")


# ======================= 3. Route Tables =======================
class TestRouteTables:
    def _rt(self, ec2, rt_id):
        return ec2.describe_route_tables(RouteTableIds=[rt_id])["RouteTables"][0]

    def test_public_rt_routes_to_igw(self, ec2, out):
        rt = self._rt(ec2, out["public_rt_id"])
        assert _default_route(rt)["GatewayId"] == out["igw_id"]
        assert out["public_subnet_id"] in [a.get("SubnetId") for a in rt["Associations"]]

    def test_private_rt_routes_to_nat(self, ec2, out):
        rt = self._rt(ec2, out["private_rt_id"])
        route = _default_route(rt)
        assert route.get("NatGatewayId") == out["nat_id"]
        assert not route.get("GatewayId", "").startswith("igw-")
        assert out["private_subnet_id"] in [a.get("SubnetId") for a in rt["Associations"]]


# ======================= 4. Security Groups =======================
class TestSecurityGroups:
    def test_public_sg_only_ssh_from_single_ip(self, ec2, out):
        perms = _sg(ec2, out["public_sg_id"])["IpPermissions"]
        assert len(perms) == 1
        p = perms[0]
        assert (p["IpProtocol"], p["FromPort"], p["ToPort"]) == ("tcp", 22, 22)
        assert not p["UserIdGroupPairs"]
        assert len(p["IpRanges"]) == 1
        net = ipaddress.ip_network(p["IpRanges"][0]["CidrIp"])
        assert net.prefixlen == 32, "Chi duoc mo SSH cho 1 IP cu the"

    def test_private_sg_only_from_public_sg(self, ec2, out):
        perms = _sg(ec2, out["private_sg_id"])["IpPermissions"]
        assert perms
        for p in perms:
            assert not p.get("IpRanges") and not p.get("Ipv6Ranges")
            assert [g["GroupId"] for g in p["UserIdGroupPairs"]] == [out["public_sg_id"]]
        assert any(p["IpProtocol"] == "tcp" and p["FromPort"] == 22 for p in perms)


# ======================= 5. EC2 =======================
class TestEc2:
    def test_public_instance(self, ec2, out):
        i = _instance(ec2, out["public_instance_id"])
        assert i["State"]["Name"] == "running"
        assert i["SubnetId"] == out["public_subnet_id"]
        assert _instance_sgs(i) == [out["public_sg_id"]]
        assert i.get("PublicIpAddress"), "Public EC2 phai co Public IP"

    def test_private_instance(self, ec2, out):
        i = _instance(ec2, out["private_instance_id"])
        assert i["State"]["Name"] == "running"
        assert i["SubnetId"] == out["private_subnet_id"]
        assert _instance_sgs(i) == [out["private_sg_id"]]
        assert not i.get("PublicIpAddress"), "Private EC2 khong duoc co Public IP"

    @pytest.mark.parametrize("key", ["public_instance_id", "private_instance_id"])
    def test_imdsv2_required(self, ec2, out, key):
        assert _instance(ec2, out[key])["MetadataOptions"]["HttpTokens"] == "required"


# ============ 6. Ket noi thuc te (can SSH_KEY_PATH) ============
SSH_KEY = os.environ.get("SSH_KEY_PATH")
SSH_OPTS = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10", "-o", "BatchMode=yes"]


def _ssh(target, cmd, jump=None):
    args = ["ssh", "-i", os.path.expanduser(SSH_KEY), *SSH_OPTS]
    if jump:
        # Ap dung cung option/key cho may trung gian
        args += ["-o", f"ProxyCommand=ssh -i {os.path.expanduser(SSH_KEY)} "
                       f"{' '.join(SSH_OPTS)} -W %h:%p ec2-user@{jump}"]
    return subprocess.run(args + [f"ec2-user@{target}", cmd],
                          capture_output=True, text=True, timeout=60)


@pytest.mark.skipif(not SSH_KEY, reason="Dat SSH_KEY_PATH de chay test ket noi")
class TestConnectivity:
    @pytest.fixture(scope="class")
    def ips(self, ec2, out):
        pub = _instance(ec2, out["public_instance_id"])
        priv = _instance(ec2, out["private_instance_id"])
        nat = ec2.describe_nat_gateways(NatGatewayIds=[out["nat_id"]])["NatGateways"][0]
        return {"public": pub["PublicIpAddress"], "private": priv["PrivateIpAddress"],
                "nat": nat["NatGatewayAddresses"][0]["PublicIp"]}

    def test_ssh_to_public_instance_from_internet(self, ips):
        r = _ssh(ips["public"], "echo ok")
        assert r.returncode == 0 and r.stdout.strip() == "ok", r.stderr

    def test_ssh_to_private_instance_via_public(self, ips):
        r = _ssh(ips["private"], "hostname -I", jump=ips["public"])
        assert r.returncode == 0, r.stderr
        assert ips["private"] in r.stdout

    def test_private_instance_reaches_internet_via_nat(self, ips):
        r = _ssh(ips["private"], "curl -s --max-time 10 https://checkip.amazonaws.com",
                 jump=ips["public"])
        assert r.returncode == 0, r.stderr
        assert r.stdout.strip() == ips["nat"], "Traffic ra Internet phai di qua NAT EIP"
