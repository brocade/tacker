==========================================================
Installation and Configuration of BSC management driver
==========================================================

After a successful tacker devstack installation, follow the below steps to
install and configure BSC management driver on Ubuntu

1. Create directory "bsc" in path 
"/opt/stack/tacker/tacker/vm/mgmt_drivers/"

2. Copy the below files to the above created directory from give tar file
    __init__.py

    bsc.py
    
3. Edit "/opt/stack/tacker/setup.cfg" file to add the below entry under
section "tacker.servicevm.mgmt.drivers = "

    bsc = tacker.vm.mgmt_drivers.bsc.bsc:DeviceMgmtBsc
    
4. Edit "/etc/tacker/tacker.conf" to add the below entry
    mgmt_driver = bsc
    
5. From the "/opt/stack/tacker" directory, execute
    "sudo python setup.py install"
    
6. Restart the "tacker" service for the installation and configuration
changes to take effect.

========================================================================
Applying configuration to VRouter from python-tackerclient during create
========================================================================
1. Copy the bsc_vnfd_template.yaml, vnfcreate.yaml, bvcconfig.yaml and edit accordingly

2. Upload the vnfd template "bsc_vnfd_template.yaml" using command
   tacker vnfd-create --vnfd-file <path to VNFD file> --name <VNFD_name>

3. For VNF create, execute the tacker client vnf-create as below
    tacker vnf-create --vnfd-name <vnfd_name> --config-file <path to config file 'bvcconfig.yaml'> --param-file <path to param value file 'vnfcreate.yaml'> --name <vnf_name>
