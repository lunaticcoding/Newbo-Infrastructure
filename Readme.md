# Setup K3s Cluster on Hetzner Cloud with Terraform 

```bash
# Set your IP in Hetzner Cloud
curl -s ifconfig.me


# Create
terraform apply -var-file .tfvars  

# Get the kube config
scp -i ~/.ssh/hetzner_terraform cluster@<IP_ADDRESS>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
scp -i ~/.ssh/hetzner_terraform cluster@128.140.54.50:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# And set the correct IP address in 
vim ~/.kube/config

# Destroy
terraform destroy -var-file .tfvars
```


# Trouble Shooting

If you recreated the master node and you are unable to connect via SSH, you may need to remove the old SSH key from the known hosts file. You can do this by running:
```
ssh-keygen -R <IP_ADDRESS>
ssh-keygen -R 128.140.54.50
```