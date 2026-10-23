# Windows Server Migration from AWS to Azure Using Azure Migrate

This project moves a Windows Server running on AWS into Azure using Microsoft's Azure Migrate service. It covers finding the server, checking that it is ready, copying its disk to Azure, testing the copy, and switching over.

> **Status:** Complete. The server was discovered, assessed, replicated, tested, cut over and verified in Azure, then both clouds were torn down. Final cost figures are noted in the Results table once the bills post.

### 🎬 Video Walkthrough

*Loom link coming after recording.*

---

## Project Overview

### What this project does, in plain English

Think of it like moving house. Before you move, someone walks through your current home and writes down what you have (**discovery**). Then they tell you how big the new place needs to be and what it will cost (**assessment**). The movers start packing and shipping your things while you keep living there (**replication**). You visit the new place once to make sure everything arrived and works (**test migration**). Then you hand over the keys and move in for good (**cutover**).

That is the whole project. The "house" is a Windows Server on AWS, and the "new place" is a virtual machine in Azure.

Where the analogy breaks down: in a real move your old house is empty afterward. Here, the AWS server keeps running until you shut it down, and Azure keeps copying any changes until the moment you switch.

### Why it matters

Companies move servers between clouds all the time: to cut costs, to meet compliance rules, or because they bought a company that runs on a different platform. Knowing how to plan and run that move, and how to check that nothing broke, is a core skill for cloud and infrastructure roles.

### What gets built

- **On AWS:** a network (VPC), one Windows Server 2022 instance to migrate, and two helper servers (appliances) that Azure Migrate needs.
- **On Azure:** a landing network, a storage account that holds the copied data, an Azure Migrate project, and finally the migrated VM.
- **Both sides are built with Terraform** in two separate folders, so each cloud can be torn down on its own.

### Skills demonstrated

- Cloud-to-cloud migration with Azure Migrate: discover, assess, replicate, test, cut over
- Infrastructure as Code with Terraform across two providers (AWS and Azure)
- AWS networking: VPC, subnet, internet gateway, route table, security groups
- Azure networking: resource groups, VNet, subnet, NSG
- Firewall rules scoped to exactly the traffic the migration needs
- Planning a test migration before cutover to lower risk
- Clean teardown across two clouds to stop charges

---

## Project Structure

```
aws-to-azure-migrate/
├── README.md
├── architecture.drawio        # editable diagram (open in draw.io)
├── images/
│   ├── architecture.png       # exported from draw.io
│   └── ...                    # screenshots, named by step
├── aws-side/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars       # NOT committed (contains passwords)
├── azure-side/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars       # NOT committed
└── .gitignore
```

---

## Architecture Diagram

![Architecture diagram](images/architecture.png)


### How it works

1. **Discover.** The discovery appliance (a helper server inside AWS) logs into the source server over WinRM and collects its details: OS, CPU, memory, disks.
2. **Assess.** The appliance sends that inventory to the Azure Migrate project. Azure checks for blockers and recommends a VM size and monthly cost.
3. **Replicate.** A small agent called the Mobility service runs on the source server. It sends disk changes to the replication appliance, which uploads them to a storage account in Azure.
4. **Test.** Azure builds a temporary VM from the copied disk so I can confirm it boots, then deletes it.
5. **Cut over.** Azure builds the final VM from the latest copy. That VM is the migrated server.

### Key terms

| Term | What it means |
|---|---|
| **Azure Migrate** | Microsoft's service for moving servers into Azure. It tracks every step in one project. |
| **Appliance** | A helper server that runs Azure Migrate software. This project uses two: one for discovery, one for replication. |
| **Mobility service** | A small agent installed on the server being moved. It watches the disk and sends changes. |
| **Replication** | Continuously copying the server's disk to Azure while the server keeps running. |
| **Cutover** | The final switch, when the Azure copy becomes the real server. |
| **VPC / VNet** | A private network in the cloud. VPC is AWS's name, VNet is Azure's. |
| **Security group / NSG** | A firewall that decides which traffic is allowed in or out. Security group is AWS's name, NSG is Azure's. |

---

## Prerequisites

- An AWS account and an Azure subscription
- Terraform, AWS CLI, and Azure CLI installed locally
- A Remote Desktop client (Microsoft Remote Desktop on Mac, `mstsc` on Windows)
- About 4–6 hours, mostly waiting on replication

Check both clouds are connected before starting:

```bash
aws sts get-caller-identity
az account show
```

Both should return account details with no errors.

---

## Naming Conventions Used

| Resource | Value |
|---|---|
| AWS VPC | `vpc-migrate-kweku` (10.0.0.0/16) |
| AWS subnet | `snet-migrate-kweku` (10.0.1.0/24) |
| Source server | `ec2-migrate-source-kweku` (Windows Server 2022, t3.medium) |
| Security group | `migrate-source-sg-kweku` (AWS blocks names starting with `sg-`) |
| Azure staging resource group | `rg-migrate-staging-kweku` |
| Azure target resource group | `rg-migrate-target-kweku` |
| Azure VNet | `vnet-migrate-kweku` (10.1.0.0/16) |
| Azure subnet | `snet-migrate` (10.1.1.0/24) |
| Replication storage | `stmigratekweku` |
| Azure Migrate project | `migrate-project-kweku` |
| Regions | AWS `us-east-1`, Azure `East US` |
| Tags | `project = azure-migrate-lab`, `owner = kweku`, `managed_by = terraform` |

The two networks use different address ranges (10.0.x.x and 10.1.x.x) so they never overlap if a VPN is added later.

---

## What I'm Changing from the Base Lab

While reading the base lab against Microsoft's documentation for AWS migrations, I found a few things that would cause the build to fail or that describe the process incorrectly. These are the changes I'm making:

1. **It's agent-based, not agentless.** Microsoft treats AWS servers as physical servers. That means the Mobility service agent has to be installed on the source server. The base lab says nothing gets installed on the source, which isn't accurate for AWS.
2. **The appliances move into the AWS network.** Microsoft requires the source server to have a direct network path to the replication appliance (ports 443 and 9443). The base lab puts both appliances in Azure with no VPN, which would block replication. Placing them in the same AWS VPC as the source server fixes that.
3. **No AWS access keys for Azure Migrate.** Discovery for AWS servers uses the server's Windows login over WinRM, not AWS API keys. I'm removing the IAM user, access keys, and snapshot permissions, which also removes an unneeded credential.
4. **Security group rules match the real traffic.** RDP from my IP only, WinRM 5985 from the discovery appliance, and 443 + 9443 from the source server to the replication appliance. Nothing else open inbound.
5. **Clearer resource group name.** The base lab's Azure group is called "source," which is confusing since the source is in AWS. I renamed it to "staging."
6. **Small fixes:** security group name no longer starts with `sg-`, the appliance VM name matches across steps, and the teardown no longer refers to a CLI-built VM that Terraform now manages.

---

## What I Actually Built

The plan above changed once it met real quotas and requirements. This is what I ran.

| Item | Planned | What I ran | Why |
|---|---|---|---|
| AWS account | free plan | **new paid account** | The free plan could not launch instances big enough for Microsoft's appliance minimums |
| Discovery appliance | m5.2xlarge | m5.2xlarge | 8 vCPU / 32 GB |
| Replication appliance | c5.2xlarge | **c5.4xlarge** | The installer counts **physical cores**. 8 vCPUs is only 4 cores (hyperthreading), so it needs 16 vCPUs |
| Replication cache disk | 300 GB | **620 GB** | The installer aborts without about 600 GB free |
| AWS vCPU limit | 5 (new account) | raised to **32** | 8 + 16 + 2 vCPUs does not fit in 5 |
| Azure VM size | assessment pick | **D2s_v4** | The source boots BIOS, so Azure builds a Generation 1 VM. v6 and v7 sizes only boot Generation 2 |
| Azure vCPU quota | | 4 in East US | The wizard's default size (M8-2ms) would exceed it |

---

## Cost Estimate

The base lab estimates **about $5–8** if everything is built and destroyed within one day. Moving the appliances to AWS changes the mix, so I'll update this with my actual bill after the build.

**Destroy everything as soon as you finish.** Two clouds billing at once adds up quickly.

---

## Project Steps

Screenshot notes are marked with 📸. Save them in `images/` using the suggested file names.

### Step 1: Set Up the Project Folders

Create two Terraform folders so each cloud can be built and destroyed separately:

```bash
mkdir aws-to-azure-migrate && cd aws-to-azure-migrate
mkdir aws-side azure-side images
```

Add `terraform.tfvars`, `*.tfstate`, and `.terraform/` to `.gitignore` before writing any code. The tfvars files hold passwords.

📸 **Screenshot `01-folder-structure.png`:** your terminal or file explorer showing the `aws-side` and `azure-side` folders.

![folder structure](images/01-folder-structure.png)


---

### Step 2: Build the AWS Side

`aws-side/main.tf` creates:

- The VPC, subnet, internet gateway, and route table
- The source Windows Server (the one being migrated)
- Two more Windows servers: the **discovery appliance** and the **replication appliance**
- Security groups with the rules from the changes list above

Deploy it:

```bash
cd aws-side
terraform init
terraform plan
terraform apply
```

Windows servers take a few extra minutes to finish starting after `apply` completes.

📸 **Screenshot `02-aws-vpc.png`:** the VPC `vpc-migrate-kweku` and its resource map: one subnet in `us-east-1a`, the route tables, and the internet gateway.

![AWS VPC](images/02-aws-vpc.png)

📸 **Screenshot `03-aws-ec2-console.png`:** the AWS EC2 console showing all three instances in the **Running** state.

![aws ec2 console](images/03-aws-ec2-console.png)


---

### Step 3: Confirm the Source Server Works

Connect with Remote Desktop to the source server's public IP (`terraform output ec2_public_ip`), user `Administrator`, and the password from `terraform.tfvars`.

This is the "before" picture. Note the hostname and OS version so you can compare later.

📸 **Screenshot `04-source-server-desktop.png`:** the Windows Server desktop, ideally with **System → About** open showing the hostname and OS version.

![source server desktop](images/04-source-server-desktop.png)


---

### Step 4: Build the Azure Side

`azure-side/main.tf` creates the staging resource group, the VNet and subnet, the storage account for replication, the target resource group, and the NSG for the migrated VM.

```bash
cd ../azure-side
terraform init
terraform plan
terraform apply
```

📸 **Screenshot `05-azure-apply.png`:** the `Apply complete!` line.

![azure apply](images/05-azure-apply.png)

📸 **Screenshot `06-azure-resource-groups.png`:** the Azure portal showing both resource groups and what's inside them.

![azure resource groups](images/06-azure-resource-groups.png)


---

### Step 5: Create the Azure Migrate Project

Terraform can't create an Azure Migrate project, so this one is done in the portal:

1. Search **Azure Migrate** → **Create project**
2. Resource group: `rg-migrate-staging-kweku`
3. Name: `migrate-project-kweku`, Geography: United States

📸 **Screenshot `07-migrate-project.png`:** the project's overview page.

![migrate project](images/07-migrate-project.png)


---

### Step 6: Set Up the Discovery Appliance

1. In the Migrate project, go to **Discover**, choose **Physical or other (AWS, GCP, etc.)**, name the appliance, and click **Generate key**. Save the key.
2. Remote Desktop into the discovery appliance EC2 instance. Download and extract the installer, then run `AzureMigrateInstaller.ps1` as Administrator and choose **Physical or other**, **Azure Public**, **Public endpoint**.
3. In the configuration manager that opens, paste the project key and sign in to Azure to register.
4. Add a credential: type **Windows Server**, user `Administrator`, and the source server's password.
5. Add the source server's **private IP** as the discovery source (both are in the same VPC), then click **Start discovery**.

📸 **Screenshot `08-appliance-registered.png`:** the configuration manager showing "Successfully registered."

![appliance registered](images/08-appliance-registered.png)

📸 **Screenshot `09-discovery-validated.png`:** the discovery source showing "Validation successful."
📸 **Screenshot `10-discovered-servers.png`:** Azure Migrate's discovered servers list with the source server in it.

![discovered servers](images/10-discovered-servers.png)


---

### Step 7: Run the Assessment

1. In the Migrate project, click **Assess → Azure VM**
2. Settings: East US, performance-based sizing, no reserved instances
3. Create a group called `aws-ec2-group`, add the source server, and create the assessment

What to look for:
- **Readiness:** "Ready for Azure" means no blockers. "Ready with conditions" or "Not ready" lists what needs fixing.
- **Recommended VM size** and **monthly cost estimate**

Skip **Create wave**. That's for moving hundreds of servers in batches.

📸 **Screenshot `11-assessment-readiness.png`:** the readiness result.

![assessment readiness](images/11-assessment-readiness.png)

📸 **Screenshot `12-assessment-size-cost.png`:** the recommended size and cost estimate.

![assessment size cost](images/12-assessment-size-cost.png)


---

### Step 8: Set Up the Replication Appliance

1. In the Migrate project, go to **Migration and modernization → Discover**, choose **Physical or other**, target region East US, and click **Create resources**. Azure creates the vault it needs here.
2. There is no download button in the portal. The PowerShell installer comes from the documentation link (`aka.ms/V2ARcmApplianceCreationPowershellZip`). Download it on the replication server, extract it, and run `DRInstaller.ps1` from the **inner** folder as Administrator.
3. In the configuration manager: let the prerequisite checks pass (including the core count), choose **NAT IP** with the appliance's *private IP* (not FQDN, because EC2 Windows hostnames do not resolve between instances), register with the key using the device-code login, tick "I do not have vCenter", and add the source server under **Physical server details**.

Microsoft says the replication appliance can't be the same machine as the discovery appliance, which is why there are two.

📸 **Screenshot `13-replication-appliance-registered.png`:** the replication appliance showing as connected.

![replication appliance registered](images/13-replication-appliance-registered.png)


---

### Step 9: Install the Mobility Service on the Source Server

With the current appliance there is nothing to install by hand. When you click **Replicate**, the replication appliance **pushes** the Mobility service to the source server over remote WMI and SMB.

That needs two things in place first:
- AWS: the source security group allows the replication appliance on ports 135, 445, 5985-5986 and 49152-65535 (a Terraform rule scoped to the appliance's security group only)
- Windows on the source: the WMI, DCOM and File and Printer Sharing firewall rules enabled, with the network profile set to Private

The agent is the part that sends disk changes. The job step "Installing Mobility Service and enabling replication" took about 19 minutes.

📸 **Screenshot `14-mobility-agent-installed.png`:** the install completing on the source server.

![mobility agent installed](images/14-mobility-agent-installed.png)


---

### Step 10: Start Replication

1. **Migration and modernization → Replicate**
2. Choose **Physical or other**, pick the replication appliance, and select the source server
3. Target: `rg-migrate-target-kweku`, storage `stmigratekweku`, VNet `vnet-migrate-kweku`, subnet `snet-migrate`
4. Leave the cache storage on auto-create and Hybrid Benefit unticked, then click **Replicate**. The size and test network can only be changed after the first recovery point exists (status **Protected**), so edit them then

The first full copy takes roughly 30–60 minutes for a 30 GB disk. Wait for the status to change from **Initial replication** to **Protected**.

📸 **Screenshot `15-replication-in-progress.png`:** the replicating machines list showing progress.

![replication in progress](images/15-replication-in-progress.png)

📸 **Screenshot `16-replication-synchronized.png`:** the item healthy with the test migration time and a recent "Last synchronized" time (replication keeps running after the test).

![replication synchronized](images/16-replication-synchronized.png)


---

### Step 11: Run a Test Migration

1. Open the replicating server and click **Test migration**, using `vnet-migrate-kweku`
2. When the test VM appears, connect to it and confirm Windows boots and the hostname matches
3. Click **Clean up test migration**

If the test fails, read the reason from the job's task detail. Mine failed because the size I chose could not boot a Generation 1 VM (see Troubleshooting).

This is the dress rehearsal. Skipping it in a real migration is how outages happen.

📸 **Screenshot `17-test-migration-status.png`:** the item showing the test migration time and a healthy status.

![test migration status](images/17-test-migration-status.png)

📸 **Screenshot `18-test-cleanup.png`:** the cleanup confirmation.

---

### Step 12: Cut Over

1. Open the replicating server and click **Migrate**
2. For a lab, choose **No** on shutting down the source, so you can compare both servers. In production you'd choose **Yes**: it shuts the source down, copies the last changes (no data loss), and avoids two live copies.

📸 **Screenshot `19-cutover-complete.png`:** the item showing **Failover completed**.

![cutover complete](images/19-cutover-complete.png)


---

### Step 13: Verify the Migrated VM

1. In `rg-migrate-target-kweku`, find the new VM
2. Attach a public IP and the NSG `nsg-migrate-target-kweku` to its network interface
3. Connect with Remote Desktop using the original `Administrator` password
4. Confirm the hostname and OS version match what you noted in Step 3

The IP address will be different from AWS. That's expected when changing clouds.

📸 **Screenshot `20-migrated-vm-desktop.png`:** the migrated VM's **System → About** page, side by side with Step 3's screenshot if possible. This is the most important screenshot in the project.

![migrated VM About page](images/20-migrated-vm-desktop.png)

---

### Step 14: Tear Everything Down

Order matters:

1. **Stop replication** in Azure Migrate and wait for it to confirm
2. `terraform destroy` in `aws-side`
3. Delete `rg-migrate-target-kweku` (it holds the migrated VM, which Terraform doesn't track)
4. `terraform destroy` in `azure-side`
5. Delete the Azure Migrate project and the vault Azure created, if they remain

Two things blocked the Azure delete, and both are worth knowing:
- **A resource lock.** Azure Migrate puts a `CanNotDelete` lock on the cache storage account it creates. Remove the lock (`az lock delete`) before deleting the resource group.
- **MFA.** With Entra security defaults on, the CLI refuses deletes until you sign in again with MFA (`az login --use-device-code`).


📸 **Screenshot `21-aws-destroyed.png`:** `Destroy complete!` for AWS.

![aws destroyed](images/21-aws-destroyed.png)

`terraform destroy` removed all 15 AWS resources (three servers, the VPC, subnet, internet gateway, route table, security groups and rules). I then checked the account: 0 servers, 0 disks, 0 networks left.

After the deletes, the subscription's resource groups were `NetworkWatcherRG` (created by Azure) and `rg-lab05-kweku` (a different lab). Both migrate groups were gone.

---

## Results

| Check | Result |
|---|---|
| Source server discovered | ✅ EC2AMAZ-AJCH2IO, Windows Server 2022, 29 GB disk, BIOS boot |
| Assessment readiness | ✅ Ready, no migration blockers (Windows support status: Extended) |
| Recommended Azure VM size | Standard_D2ls_v5 |
| Estimated monthly cost in Azure | **$148.97** (compute 131.69, storage 2.40, security 14.88), with Hybrid Benefit off |
| Time for initial replication | about 12 minutes of copying, then about 20 minutes to the first recovery point (Protected at 6:48 PM EDT) |
| Test migration booted | ✅ Hostname EC2AMAZ-AJCH2IO, Windows Server 2022 build 20348.5761, Azure VM agent Ready |
| Cutover completed | ✅ "Failover completed", job took about 2.5 minutes (chose **No** on shutting down the source so both copies stayed up for comparison) |
| Hostname and OS match source | ✅ Final VM: hostname EC2AMAZ-AJCH2IO, Windows Server 2022 Datacenter 21H2, build 20348.5761, the same as the AWS source. Only the hardware differs (8 GB RAM on D2s_v4) |
| Teardown | ✅ AWS: 0 servers, 0 disks, 0 networks left. Azure: both migrate resource groups deleted |
| Actual total cost (AWS + Azure) | not yet posted (billing lags about a day). Running estimate while everything was up: about $1.70 per hour |

**What I'd note in this section:** anything that broke, what fixed it, and how long each phase actually took compared to the estimates.

---

## Project Breakdown

A plain-language summary of what this project was, why it matters, and what I would do differently.

### What I did

I moved a live Windows Server 2022 from AWS to Azure using Microsoft's migration service, Azure Migrate, and built both sides with Terraform.

1. **Discover.** A helper server scanned the machine and reported its details to Azure.
2. **Assess.** Azure judged the machine **Ready** with no blockers, and estimated about **$148.97 a month**.
3. **Replicate.** A second helper copied the disk to Azure while the original kept running.
4. **Test.** Azure built a temporary copy and booted it, without touching the real server.
5. **Cut over.** Azure built the real VM. It came up with the **same hostname, edition and build number (20348.5761)** as the AWS original, which is the main proof the move worked.
6. **Tear down.** Both clouds were removed in the right order so nothing kept billing.

### Why it matters

- Moving servers between clouds is routine work: after acquisitions, for cost, or for compliance.
- It shows a process (discover, assess, test, cut over), not just clicking through a wizard.
- Everything is code and documented, so someone else can rebuild it from this repo.
- The cleanup was done and verified, which is often skipped.

### An alternative approach

- **Agentless migration** needs nothing installed on the source, but Azure Migrate does not offer it for AWS servers. It treats them as physical machines, which is why this project is agent-based.
- **Rebuild instead of move.** For an app with a clean install process, redeploying on a fresh Azure VM (or containers) is often better long term, but it needs deep knowledge of the app.
- **At larger scale,** group servers into waves and connect the clouds with a VPN so machines can talk during the move.

### What I learned

The hard part was not the wizard. It was finding the real cause behind generic errors, at the right layer each time.

- **Vendor requirements are literal.** The replication appliance counts physical cores, so a size with "8 vCPUs" still failed.
- **Check the firewall at every hop.** Three separate blocks looked like three different errors.
- **Read the real log.** The portal said "internal error". The answer was in the Push Install Agent log and the job's task detail.
- **BIOS or UEFI decides the Azure VM generation,** which limits the sizes that can boot.
- **New accounts hit quotas in both clouds** (5 vCPUs on AWS, 4 on Azure).
- **A test migration is where the surprises show up cheaply.**

### Honest numbers

- **Time:** about a full day, mostly troubleshooting.
- **Cost:** about $1.70 an hour while everything was running (an estimate, not a bill). The assessment's $148.97 per month includes the Windows license because Hybrid Benefit was off.

---

## Security Decisions

- **RDP limited to my IP.** Open RDP to the internet is one of the most scanned ports. Even for a short lab, there's no reason to allow it from everywhere.
- **Only the ports the migration needs.** WinRM (5985) for discovery and 443/9443 for replication, each allowed only from the specific appliance that uses it.
- **No AWS access keys.** Azure Migrate doesn't need them for AWS servers, so creating them would just add a long-lived credential that could leak.
- **Passwords stay out of Git.** `terraform.tfvars` and state files are in `.gitignore`. State files can contain sensitive values.
- **Test before cutover.** A test migration confirms the server boots in Azure before anything is committed.
- **Separate staging and target resource groups.** Migration tooling can be deleted without touching the migrated VM.
- **Extra source-server rules are scoped to one security group.** The replication appliance's group can reach the source on the migration ports. Nothing is opened to the internet.
- **Screenshots are redacted.** Subscription IDs, account emails, project keys and public IPs are blurred.

---

## Troubleshooting / Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `cannot begin with sg-` | AWS reserves that prefix for its own IDs | Name the group `migrate-source-sg-kweku` |
| `collecting instance settings: empty result` | AMI ID doesn't exist in your region | Look up the latest Windows Server 2022 AMI with `aws ec2 describe-images` and update `windows_ami` |
| `azurerm_migrate_project` not supported | Terraform's Azure provider can't create Migrate projects | Create the project in the portal (Step 5) |
| Discovery validation fails | WinRM blocked, or wrong password | Check the security group allows 5985 from the discovery appliance, and re-enter the credential |
| Source server missing from the Replicate list | Mobility service not installed or not registered | Repeat Step 9 and confirm the agent shows up on the replication appliance |
| Replication stuck at 0% | Source can't reach the replication appliance | Confirm 443 and 9443 are allowed from the source to the replication appliance |
| Can't RDP to the migrated VM | No public IP or no NSG on its network interface | Attach both (Step 13) |
| Migrated VM has a different IP | Azure assigns a new address | Expected. Update DNS if anything points to the old IP |
| `vault is not empty` on destroy | Replication items still registered | Stop replication and remove items from the vault, then retry |
| New AWS account blocks launches | Default limit is 5 Standard vCPUs (`VcpuLimitExceeded`) | Request a quota increase in Service Quotas (approved at 32) |
| Replication appliance: "Memory and CPU validation failed ... only 4 CPU cores" | `c5.2xlarge` has 8 vCPUs but only 4 physical cores | Resize to `c5.4xlarge` (16 vCPUs, 8 cores) |
| Configuration manager link gives `DNS_PROBE_FINISHED_NXDOMAIN` from another server | Windows computer names do not resolve between EC2 instances | Use the private IP (NAT IP option) |
| Physical server status **Error** in the appliance | The source security group only allowed port 5985 from the discovery appliance | Add rules from the replication appliance's group: 135, 445, 5985-5986, 49152-65535 |
| Job fails at "Installing Mobility Service" (codes 539 and 320000) | The push stopped at the remote WMI step, so the agent was never installed | Enable the WMI-In and DCOM-In rules, set the network profile to Private, retry. Log: `C:\Program Files\Microsoft Azure Push Install Agent\PushInstallService.log` |
| Test migration fails: `VM size 'Standard_D2ls_v7' cannot boot Hypervisor Generation '1'` | A BIOS source becomes a Generation 1 VM | Use a size that supports Gen 1 (D2s_v4) |
| Target size shows `Standard_M8-2ms` | Wizard default, and above a 4-vCPU Azure quota | Edit to a 2-vCPU size once the status is Protected |
| Portal shows "In error / Action pending" after a failed test | Health 161011: no successful test migration yet | Clean up the failed test, fix the size, run the test again |

![Replication appliance core check failure](images/troubleshoot-1-replication-cpu-check-failed.png)

---

## Key Takeaways

These are the ideas this project is built to show, updated with what actually happened.

- **A migration is a process, not a button.** Discover, assess, replicate, test, cut over. Each step catches a different kind of problem.
- **Assessment is where you find blockers cheaply.** Fixing a "Not ready" result before replication saves hours.
- **Network paths decide whether it works.** The source server has to reach the replication appliance. Getting the firewall rules and placement right matters more than any setting in the portal.
- **Always test first.** A test migration costs minutes. A failed cutover can cost a day of downtime.
- **Clean up in order.** Two clouds and several manual resources mean `terraform destroy` alone won't catch everything.
- **Vendor requirements are literal.** The replication appliance counts physical cores, so a size with "8 vCPUs" still failed.
- **Check the firewall at every hop.** Three separate blocks (discovery to source, appliance to source, source to appliance) each showed up as a different error.
- **Read the real log.** The portal said "internal error". The answer was in the Push Install Agent log and the job's task detail.
- **BIOS or UEFI decides the Azure VM generation,** and the generation limits which sizes can boot.
- **Quotas bite on new accounts** in both clouds (5 vCPUs on AWS, 4 on Azure).

---

## Reference

- [Microsoft: Discover, assess, and migrate AWS VMs to Azure](https://learn.microsoft.com/azure/migrate/tutorial-migrate-aws-virtual-machines)
- [Microsoft: Migrate machines as physical servers to Azure](https://learn.microsoft.com/azure/migrate/tutorial-migrate-physical-virtual-machines)
- Base lab guide: *Azure Migration Lab: AWS EC2 to Azure using Azure Migrate*

---
**Author:** Manuel Yannick Armah

**Project:** Migrating a Windows Server from AWS to Azure with Azure Migrate

**Difficulty:** Intermediate

**Time to Complete:** 4-6 hours  (most of it troubleshooting)
