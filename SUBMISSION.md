# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `notes.md` with your commands and what you saw (optional)

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste the peering connection (`aws ec2 describe-vpc-peering-connections`). Who is the requester and who accepts? What happens if the two VPCs have overlapping CIDR blocks?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. Show the route tables on both sides. Why does peering need a route in each VPC? What would you see if you added only one?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. Show the security group rule you added on the staging server. Why do you reference the other VPC's CIDR here and not a security group name? (Hint: cross-VPC references.)

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Peering is not transitive. If VPC A peers with B and B peers with C, can A reach C? What would you use instead for ten VPCs?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Both servers report a result tag. Paste them before and after your fix and say what you changed first and what you found out second.

**Your answer:**

<!-- replace this line with your answer -->

### Q6. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q7. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
