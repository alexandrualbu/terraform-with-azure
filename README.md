I have created multiple variables with default values and used the in main.tf file.

First of all I have provisioned Terraform with azure and I provisioned azurerm with subscription, client_id, client_secret and tenant_id from my microsoft azure account.

I used locals type to create IPs within a range starting from .100 to .200 and not from .0 because some of them are protected. That list of IPs I have used it to set IPs to the network interfaces (private_ip_adress).

I started with creating a Resource group and put everything in that Resorce Group.

I created a virtual network ( private), a subnet for the network, multiple public IP adresses in order to enter with SSH in that instances.

The security group was needed to allow access from external to that instance, so the direction needed to be inbound. By default Inbound has deny all policy and outbound allow all policy over http and https.

The network interface "nics" was required by the virtual machines.

The random_password provisioned me auto-generated 16 characters. I used it because the passwords had sensitive_content = true by default

The virtual machines I have created required manadatory fields like name, location, size, os_disk, source_image reference etc.

The size was stored in a variable called size. The size value was Standard_B1ls.

The image for the instances were Ubuntu-22_04-lts.


I have set a computer name with variable computer_host_name, an admin useer called "adminuser" and its password was set after random_password.vm_password [type,name]. 

I have copied the public ssh key from local machine to the virtual machines.

I've used data type to retrieve and store the public IP's because it have me an error on host        = azurerm_public_ip.my_terraform_public_ip[count.index].ip_address. The value would be null in this case and was assigned only if terraform refresh was ran afterwards. 

In null_resource ping_command resource I have ran 2 commands. One command was ran in vms to ping between them (vm0 into vm1 and vm1 into vm0) and saved the output in a /tmp/ping_output_.txt file. The local_exec command copied the /tmp/files to local machine.

After that I have created a file in the same folder with the /tmp/ping_output, locally. 

I have put all the content of the ping commands in that single file using cat and >>(append)

The last step was to create that ping_output output variable with the content of combined_output.txt file.

I have worked in only one main.tf file the task.

To the variables I was not required to set them a type, so only default value were set.

