#!/usr/bin/env python3
import json, os, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
passed = failed = 0


def check(desc, ok, hint=""):
    global passed, failed
    if ok:
        passed += 1; print("PASS  " + desc)
    else:
        failed += 1; print("FAIL  " + desc + (("   -> " + hint) if hint else ""))


def aws(*a):
    try:
        return json.loads(subprocess.check_output(("aws",) + a + ("--output", "json"), stderr=subprocess.DEVNULL, timeout=60) or "null")
    except Exception:
        return None


check("no AWS keys in the repository", subprocess.run("git grep -lE 'AKIA[0-9A-Z]{16}' -- . ':!.lab' ':!verify.sh'", shell=True, capture_output=True, text=True).stdout.strip() == "")
F = "Name=tag:lab,Values=aws-vpc-peering"
vpcs = {next((t["Value"] for t in v.get("Tags", []) if t["Key"] == "Name"), "?"): v for v in (aws("ec2", "describe-vpcs", "--filters", F) or {}).get("Vpcs", [])}
check("the two networks exist (staging 10.1.0.0/16 and analytics 10.2.0.0/16)", sorted(vpcs) == ["analytics", "staging"], "./setup.sh")
if len(vpcs) != 2:
    print("\nNothing else can be checked.\n%d check(s) failed, %d passed" % (failed, passed)); sys.exit(1)
st, an = vpcs["staging"], vpcs["analytics"]
print("== The peering ==")
pcs = (aws("ec2", "describe-vpc-peering-connections", "--filters", "Name=status-code,Values=active") or {}).get("VpcPeeringConnections", [])
pc = next((p for p in pcs if {p["RequesterVpcInfo"]["VpcId"], p["AccepterVpcInfo"]["VpcId"]} == {st["VpcId"], an["VpcId"]}), None)
check("an ACTIVE peering connection joins staging and analytics (requested and accepted)", bool(pc))
print("== Routes (both directions) ==")
def routes(vpc):
    return [r for rt in (aws("ec2", "describe-route-tables", "--filters", "Name=vpc-id,Values=" + vpc["VpcId"]) or {}).get("RouteTables", []) for r in rt["Routes"]]
rs, ra = routes(st), routes(an)
check("staging has a route to 10.2.0.0/16 through the peering (the reply must find its way back)", bool(pc) and any(r.get("DestinationCidrBlock") == "10.2.0.0/16" and r.get("VpcPeeringConnectionId") == pc["VpcPeeringConnectionId"] for r in rs))
check("analytics has a route to 10.1.0.0/16 through the peering", bool(pc) and any(r.get("DestinationCidrBlock") == "10.1.0.0/16" and r.get("VpcPeeringConnectionId") == pc["VpcPeeringConnectionId"] for r in ra))
print("== The firewall on the staging server ==")
sgs = (aws("ec2", "describe-security-groups", "--filters", "Name=vpc-id,Values=" + st["VpcId"], "Name=group-name,Values=clippy-staging") or {}).get("SecurityGroups", [])
rules = (aws("ec2", "describe-security-group-rules", "--filters", "Name=group-id,Values=" + sgs[0]["GroupId"]) or {}).get("SecurityGroupRules", []) if sgs else []
ing = [r for r in rules if not r["IsEgress"]]
check("the staging server accepts exactly one thing: TCP 80 from 10.2.0.0/16", len(ing) == 1 and ing[0]["FromPort"] == 80 and ing[0]["ToPort"] == 80 and ing[0].get("CidrIpv4") == "10.2.0.0/16", "found %s" % [(r["FromPort"], r.get("CidrIpv4")) for r in ing])
print("== What the servers say ==")
insts = [i for r in (aws("ec2", "describe-instances", "--filters", F, "Name=tag:Name,Values=analytics-server", "Name=instance-state-name,Values=running") or {}).get("Reservations", []) for i in r["Instances"]]
tags = {t["Key"]: t["Value"] for t in (insts[0].get("Tags", []) if insts else [])}
check("the analytics server reports peer-http = ok (it just reached the staging server over the peering)", tags.get("peer-http") == "ok", "its tag says %r, last checked %s" % (tags.get("peer-http"), tags.get("peer-checked")))
print()
print(("ALL CHECKS PASSED (%d/%d)" % (passed, passed)) if failed == 0 else ("%d check(s) failed, %d passed" % (failed, passed)))
sys.exit(1 if failed else 0)
