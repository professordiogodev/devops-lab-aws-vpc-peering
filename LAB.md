# LAB | AWS VPC: Two Networks That Must Talk

## The situation

```text
#staging-platform                                        Thursday
Analytics   : our server must call the staging service. Privately.
              Not over the internet. Deadline is Monday.
Platform    : we are not putting staging on the internet for you.
Security    : agreed. Private only.
Analytics   : so... VPC peering? Peering is easy, right?
Platform    : it looks easy, and it fails silently when one piece is missing.
```

Two networks built by different people for different purposes, and a connection that has to be both private and correct. You will look at the two networks that cannot talk, build the peering halfway and watch it fail, then complete it. The ticket closes when the analytics server reaches the staging service over AWS's own network.

> **Your mission**
> - Look at two networks that cannot talk to each other
> - Create and accept a peering connection
> - Add the routes (both directions) and the one firewall rule that allows the call
> - Watch a server report, in its own tags, whether it can reach the other one
> - Tear everything down and prove it

**Time:** 60-75 min | **Cost:** a few cents (two small servers for an hour) | **You need:** an AWS administrator user, the AWS CLI v2 configured for it, Python 3 and a terminal.

---

## Part 0 - Set the scene

1. **Fork** this repository, clone it, and build the two networks:

```bash
./setup.sh
```

You get **staging** (`10.1.0.0/16`, a server at `10.1.1.10` that answers HTTP on port 80) and **analytics** (`10.2.0.0/16`, a server at `10.2.1.10`). The analytics server calls `http://10.1.1.10/` every 20 seconds and **writes the result on its own tags**: `peer-http` is `ok` or `fail`, and `peer-checked` is the time of the last try.

2. Watch the tag (give the server a minute or two to install its little script):

```bash
aws ec2 describe-instances --filters Name=tag:Name,Values=analytics-server Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].Tags[?starts_with(Key,`peer`)].[Key,Value]' --output text
```

It says `fail`. Say why, before you touch anything: there are at least three reasons, in three different places.

> **Think** Both servers have public IPs and sit in networks with an internet gateway. Why does the analytics server not simply call the staging server's public address? What is wrong with that when the security group is open to the internet?

---

## Part 1 - The peering connection

Create a peering connection **from the analytics VPC to the staging VPC** and **accept** it (you own both sides, so you accept your own request):

```bash
aws ec2 create-vpc-peering-connection --vpc-id <analytics vpc> --peer-vpc-id <staging vpc> --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=lab,Value=aws-vpc-peering}]'
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id <pcx-...>
```

(Find the VPC ids with `aws ec2 describe-vpcs --filters Name=tag:lab,Values=aws-vpc-peering`.) Check its state: `pending-acceptance`, then `active`.

> **Think** What would have happened if both networks used `10.0.0.0/16`? Why does peering refuse overlapping address ranges, and what would you do in a company that has already done it?

---

## Part 2 - The firewall, then one route

1. On the **staging** server's security group (`clippy-staging`), allow **TCP 80 from `10.2.0.0/16` only**. One rule, nothing else.
2. In the **analytics** route table add the route `10.1.0.0/16` through the peering connection. **Only that route.**

```bash
aws ec2 create-route --route-table-id <analytics rtb> --destination-cidr-block 10.1.0.0/16 --vpc-peering-connection-id <pcx-...>
```

Wait about a minute and read the tag again. It is **still `fail`**. The request now finds its way to staging, the firewall lets it in, the server answers... and the answer has no way back.

> **Think** The reply goes to `10.2.1.10`. Look at the staging route table. What does the staging subnet do with a packet for `10.2.0.0/16`? This is the single most common peering mistake.

---

## Part 3 - The second route

Add the missing route in the **staging** route table: `10.2.0.0/16` through the same peering connection. Wait for the next check (20 seconds) and read the tag again: `peer-http` is `ok`.

> **Think** Peering is **not transitive**: if A peers with B and B peers with C, A cannot reach C through B. For ten VPCs you would need 45 peering connections and 90 routes. What AWS service replaces this, and what does it cost?

---

## Part 4 - Prove it

```bash
./verify.sh
```

It reads the real peering connection (it must be active), both route tables, the staging security group (exactly one rule: TCP 80 from `10.2.0.0/16`) and the tag that the analytics server wrote about its own attempt. Fix what is red and run it again until it ends with **ALL CHECKS PASSED**.

> **Stuck?** The peering stays `pending-acceptance`: you created it but did not accept it. The tag stays `fail`: check the three things in order, peering active, a route in each VPC, and the security group on the staging server (source `10.2.0.0/16`). `InvalidParameterValue` creating a route: check the CIDR. The tag does not exist yet: the analytics server needs a minute or two after `setup.sh` to install its script.

---

## Level up (optional)

- Turn on **DNS resolution** for the peering connection and call the staging server by its private DNS name.
- Replace the CIDR in the firewall rule with the analytics server's **security group** (cross-VPC references work inside a region for peered VPCs). What is better and what is riskier?
- Draw what would change with an **AWS Transit Gateway** for three networks.
- Peer with a VPC in **another region** and compare the data-transfer prices.

<!-- teardown:start (generated by labs.py, do not edit) -->
## Tear down (mandatory)

Resources left behind cost money, keep doors open and pollute the next lab. Removing what you created is part of the job, so it is part of the submission: **you must prove it is gone**.

Do this **last**, after you have pasted your `verify` output into `SUBMISSION.md` (once you tear down, the lab can no longer be verified).

1. Run `./teardown.sh`. It deletes the peering connection, both VPCs, the servers and the role. Then run `./verify-teardown.sh`.

Then run the proof:

```bash
./verify-teardown.sh
```

It prints a list of checks and must end with **TEARDOWN VERIFIED**. If it reports leftovers, remove them and run it again. Paste the full output in your submission.
<!-- teardown:end -->

<!-- submission:start (generated by labs.py, do not edit) -->
## Submission

Answer the questions in `SUBMISSION.md` in **your fork** (paste output in code blocks where asked), push, then submit the **URL of your fork**.

**Files to commit**

- `notes.md` with your commands and what you saw (optional)

**Questions to answer**

1. Paste the peering connection (`aws ec2 describe-vpc-peering-connections`). Who is the requester and who accepts? What happens if the two VPCs have overlapping CIDR blocks?
2. Show the route tables on both sides. Why does peering need a route in each VPC? What would you see if you added only one?
3. Show the security group rule you added on the staging server. Why do you reference the other VPC's CIDR here and not a security group name? (Hint: cross-VPC references.)
4. Peering is not transitive. If VPC A peers with B and B peers with C, can A reach C? What would you use instead for ten VPCs?
5. Both servers report a result tag. Paste them before and after your fix and say what you changed first and what you found out second.
6. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.
7. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.
<!-- submission:end -->
