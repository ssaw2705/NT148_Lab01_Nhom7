"""Unit test cho tung template CloudFormation (chay offline, khong can AWS).

Chay: pytest -q cloudformation/tests
"""
from pathlib import Path

import pytest
from cfnlint.decode import decode

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "templates"


def load(name):
    path = ROOT / name if name == "main.yaml" else TEMPLATES / name
    template, matches = decode(str(path))
    assert not matches, matches
    return template


def resources_of_type(tpl, rtype):
    return {k: v for k, v in tpl["Resources"].items() if v["Type"] == rtype}


def props(tpl, logical_id):
    return tpl["Resources"][logical_id]["Properties"]


# ---------------- VPC ----------------
class TestVpc:
    tpl = load("vpc.yaml")

    def test_vpc_has_dns(self):
        p = props(self.tpl, "VPC")
        assert p["EnableDnsSupport"] is True and p["EnableDnsHostnames"] is True

    def test_public_subnet_maps_public_ip(self):
        p = props(self.tpl, "PublicSubnet")
        assert p["MapPublicIpOnLaunch"] is True
        assert p["VpcId"] == {"Ref": "VPC"}

    def test_private_subnet_has_no_public_ip(self):
        p = props(self.tpl, "PrivateSubnet")
        assert p["MapPublicIpOnLaunch"] is False
        assert p["VpcId"] == {"Ref": "VPC"}

    def test_internet_gateway_attached_to_vpc(self):
        att = props(self.tpl, "InternetGatewayAttachment")
        assert att["VpcId"] == {"Ref": "VPC"}
        assert att["InternetGatewayId"] == {"Ref": "InternetGateway"}

    def test_default_sg_only_allows_self(self):
        sg = props(self.tpl, "DefaultSecurityGroup")
        assert "SecurityGroupIngress" not in sg
        rule = props(self.tpl, "DefaultSecurityGroupSelfIngress")
        assert rule["SourceSecurityGroupId"] == {"Ref": "DefaultSecurityGroup"}
        assert "CidrIp" not in rule


# ---------------- NAT Gateway ----------------
class TestNatGateway:
    tpl = load("nat-gateway.yaml")

    def test_nat_in_public_subnet_with_eip(self):
        p = props(self.tpl, "NatGateway")
        assert p["SubnetId"] == {"Ref": "PublicSubnetId"}
        assert p["AllocationId"] == {"Fn::GetAtt": ["NatEip", "AllocationId"]}
        assert p["ConnectivityType"] == "public"

    def test_eip_in_vpc(self):
        assert props(self.tpl, "NatEip")["Domain"] == "vpc"


# ---------------- Route Tables ----------------
class TestRouteTables:
    tpl = load("route-tables.yaml")

    def test_public_route_to_igw(self):
        r = props(self.tpl, "PublicInternetRoute")
        assert r["DestinationCidrBlock"] == "0.0.0.0/0"
        assert r["GatewayId"] == {"Ref": "InternetGatewayId"}
        assert r["RouteTableId"] == {"Ref": "PublicRouteTable"}

    def test_private_route_to_nat(self):
        r = props(self.tpl, "PrivateNatRoute")
        assert r["DestinationCidrBlock"] == "0.0.0.0/0"
        assert r["NatGatewayId"] == {"Ref": "NatGatewayId"}
        assert "GatewayId" not in r

    @pytest.mark.parametrize("assoc,subnet,rt", [
        ("PublicSubnetRouteTableAssociation", "PublicSubnetId", "PublicRouteTable"),
        ("PrivateSubnetRouteTableAssociation", "PrivateSubnetId", "PrivateRouteTable"),
    ])
    def test_associations(self, assoc, subnet, rt):
        a = props(self.tpl, assoc)
        assert a["SubnetId"] == {"Ref": subnet}
        assert a["RouteTableId"] == {"Ref": rt}


# ---------------- Security Groups ----------------
class TestSecurityGroups:
    tpl = load("security-groups.yaml")

    def test_public_sg_only_ssh_from_given_ip(self):
        rules = props(self.tpl, "PublicEc2SecurityGroup")["SecurityGroupIngress"]
        assert len(rules) == 1
        r = rules[0]
        assert (r["IpProtocol"], r["FromPort"], r["ToPort"]) == ("tcp", 22, 22)
        assert r["CidrIp"] == {"Ref": "AllowedSshCidr"}

    def test_allowed_ssh_cidr_must_be_single_ip(self):
        pattern = self.tpl["Parameters"]["AllowedSshCidr"]["AllowedPattern"]
        assert pattern.endswith("/32$")

    def test_private_sg_only_from_public_sg(self):
        rules = props(self.tpl, "PrivateEc2SecurityGroup")["SecurityGroupIngress"]
        assert rules
        for r in rules:
            assert r["SourceSecurityGroupId"] == {"Ref": "PublicEc2SecurityGroup"}
            assert "CidrIp" not in r
        assert any(r["IpProtocol"] == "tcp" and r["FromPort"] == 22 for r in rules)


# ---------------- EC2 ----------------
class TestEc2:
    tpl = load("ec2.yaml")

    def test_imdsv2_required(self):
        lt = props(self.tpl, "LaunchTemplate")["LaunchTemplateData"]
        assert lt["MetadataOptions"]["HttpTokens"] == "required"

    def test_root_volume_encrypted(self):
        bdm = props(self.tpl, "Instance")["BlockDeviceMappings"][0]
        assert bdm["Ebs"]["Encrypted"] is True

    def test_public_ip_controlled_by_parameter(self):
        eni = props(self.tpl, "Instance")["NetworkInterfaces"][0]
        assert eni["AssociatePublicIpAddress"] == {"Ref": "AssociatePublicIp"}
        assert self.tpl["Parameters"]["AssociatePublicIp"]["Default"] == "false"


# ---------------- Root stack ----------------
class TestMainStack:
    tpl = load("main.yaml")

    def test_all_modules_are_nested_stacks(self):
        stacks = resources_of_type(self.tpl, "AWS::CloudFormation::Stack")
        urls = {v["Properties"]["TemplateURL"] for v in stacks.values()}
        assert urls == {
            "templates/vpc.yaml", "templates/nat-gateway.yaml",
            "templates/route-tables.yaml", "templates/security-groups.yaml",
            "templates/ec2.yaml",
        }
        for url in urls:
            assert (ROOT / url).exists()

    def test_public_and_private_instances(self):
        pub = props(self.tpl, "PublicEc2Stack")["Parameters"]
        priv = props(self.tpl, "PrivateEc2Stack")["Parameters"]
        assert pub["AssociatePublicIp"] == "true"
        assert pub["SubnetId"] == {"Fn::GetAtt": ["VpcStack", "Outputs.PublicSubnetId"]}
        assert pub["SecurityGroupId"] == {"Fn::GetAtt": ["SecurityGroupsStack", "Outputs.PublicSecurityGroupId"]}
        assert priv["AssociatePublicIp"] == "false"
        assert priv["SubnetId"] == {"Fn::GetAtt": ["VpcStack", "Outputs.PrivateSubnetId"]}
        assert priv["SecurityGroupId"] == {"Fn::GetAtt": ["SecurityGroupsStack", "Outputs.PrivateSecurityGroupId"]}

    def test_private_route_uses_nat_output(self):
        p = props(self.tpl, "RouteTablesStack")["Parameters"]
        assert p["NatGatewayId"] == {"Fn::GetAtt": ["NatGatewayStack", "Outputs.NatGatewayId"]}
        assert p["InternetGatewayId"] == {"Fn::GetAtt": ["VpcStack", "Outputs.InternetGatewayId"]}
