==========================================================
Installation and Configuration of Vyatta management driver
==========================================================

After a successful tacker devstack installation, follow the below steps to
install and configure Vyatta management driver on Ubuntu

1. Create directory "vyatta" in path 
"/opt/stack/tacker/tacker/vm/mgmt_drivers/"

2. Copy the below files to the above created directory from give tar file
    __init__.py

    ssh_connector.py

    vyatta.py
    
3. Edit "/opt/stack/tacker/setup.cfg" file to add the below entry under
section "tacker.servicevm.mgmt.drivers = "

    vyatta = tacker.vm.mgmt_drivers.vyatta.vyatta:DeviceMgmtVyatta
    
4. Edit "/etc/tacker/tacker.conf" to add the below entry
    mgmt_driver = vyatta
    
5. From the "/opt/stack/tacker" directory, execute
    "sudo python setup.py install"
    
6. Restart the "tacker" service for the installation and configuration
changes to take effect.

========================================================================
Applying configuration to VRouter from python-tackerclient during create
========================================================================
1. Copy the vnf_vrouter_template.yaml, vnfcreate.yaml, sampleconfig.yaml and edit accordingly.

2. Upload the vnfd template "vnf_vrouter_template.yaml" using command
   tacker vnfd-create --vnfd-file <path to VNFD file> --name <VNFD_name>

3. For VNF create, execute the tacker client vnf-create as below
    tacker vnf-create --vnfd-name <vnfd_name> --config-file <path to config 
    file 'sampleconfig.yam'> --param-file <path to param value file 'vnfcreate.yaml'> --name <vnf_name>

=================================================================
Applying configuration update to VRouter from python-tackerclient
=================================================================
1. Create a Vyatta VRouter VNF in tacker

2. Copy the sampleconfig.yaml and edit accordingly to apply config
changes.

3. For VNF update, execute the tacker client vnf-update command as below
    tacker vnf-update <VNF_NAME> --config-file <path to config file>
