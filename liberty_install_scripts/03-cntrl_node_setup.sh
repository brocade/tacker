#get variables defined in 01-openstack_vars
source ./02-export_var_cntrl
echo "MY_PUBLIC_IP=$MY_PUBLIC_IP"
sleep 3
read -p "Press ENTER to continue if the IP address displayed is correct or CTRL-C to exit"

#install openstack client
sudo apt-get install -y python-openstackclient

### Install RabbitMQ
echo "RABBITMQ INSTALL START"
sudo apt-get install -y rabbitmq-server
sudo rabbitmqctl add_user $RABBIT_USER $RABBIT_PWD
sudo rabbitmqctl set_permissions $RABBIT_USER ".*" ".*" ".*"

#Restart RabbitMQ
sudo service rabbitmq-server restart
echo "RABBITMQ INSTALL END"
sleep 3

### MySQL install
echo "MYSQL INSTALL START"
sudo apt-get install -y debconf-utils
cat <<EOF | sudo debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PWD
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PWD
mysql-server-5.5 mysql-server/start_on_boot boolean true
EOF

sudo apt-get install -y mysql-server python-mysqldb

sudo sed -i "s/127.0.0.1/$MYSQL_IP\nskip-name-resolve\ncharacter-set-server = utf8\ncollation-server = utf8_general_ci\ninit-connect = SET NAMES utf8/g" /etc/mysql/my.cnf
sudo sed -i "s|#max_connections|\nmax_connections = 200\n#max_connections|g" /etc/mysql/my.cnf

sudo service mysql restart
echo "MYSQL INSTALL END"
sleep 5

#Keystone nstall
echo "KEYSTONE INSTALL START"

mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $KEYSTONE_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $KEYSTONE_DB.* TO '$KEYSTONE_DBUSER'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $KEYSTONE_DB.* TO '$KEYSTONE_DBUSER'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

cat <<EOF | sudo tee /etc/init/keystone.override
manual
EOF

sudo apt-get install -y keystone apache2 libapache2-mod-wsgi memcached python-memcache

sudo sed -i "s|#admin_token = $SERVICE_TOKEN|admin_token = $SERVICE_TOKEN|g" /etc/keystone/keystone.conf
sudo sed -i "s|#servers = localhost:11211|servers = localhost:11211|g" /etc/keystone/keystone.conf
sudo sed -i "s|#provider = uuid|provider = uuid\ndriver = memcache|g" /etc/keystone/keystone.conf
sudo sed -i "s|revoke]|revoke]\ndriver = sql\n|g" /etc/keystone/keystone.conf
sudo sed -i "s|#verbose = true|verbose = true|g" /etc/keystone/keystone.conf

sudo sed -i "s|connection = sqlite:////var/lib/keystone/keystone.db|connection = mysql+pymysql://$KEYSTONE_DBUSER:$KEYSTONE_DBPASS@$MYSQL_IP/$KEYSTONE_DB|g" /etc/keystone/keystone.conf

sudo keystone-manage db_sync

sudo sed -i '0,/#/s/#/ServerName '$MY_IP'\n#/' /etc/apache2/apache2.conf

cat <<EOF | sudo tee /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
EOF

sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled

sudo service apache2 restart

# Remove the default SQLite database 
sudo rm /var/lib/keystone/keystone.db

#sudo service keystone start
echo "KEYSTONE INSTALL END"
#sleep 10

export OS_TOKEN=$SERVICE_TOKEN
export OS_URL=http://$MY_IP:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack service create --name $KEYSTONE_SVC_NAME --description "OpenStack Identity" identity
sleep 3
KEYSTONE_SVC_ID=`openstack service show $KEYSTONE_SVC_NAME | awk '/ id / { print $4 }'`

openstack endpoint create --region $REGION identity public http://$KEYSTONE_IP:5000/v2.0
openstack endpoint create --region $REGION identity internal http://$KEYSTONE_IP:5000/v2.0
openstack endpoint create --region $REGION identity admin http://$KEYSTONE_IP:35357/v2.0

openstack project create --domain default --description "Admin Project" $ADMIN_TENANT_NAME
openstack user create --domain default --password $ADMIN_USER_PWD $ADMIN_USER
openstack role create $ADMIN_ROLE
openstack role add --project $ADMIN_TENANT_NAME --user $ADMIN_USER $ADMIN_ROLE
openstack project create --domain default --description "Service Project" $SERVICE_TENANT
openstack project create --domain default --description "Demo Project" $DEMO_TENANT_NAME
openstack user create --domain default --password $DEMO_USER_PWD $DEMO_USER
openstack role create $USER_ROLE
openstack role add --project $DEMO_TENANT_NAME --user $DEMO_USER $USER_ROLE

cat << EOF | sudo tee ~/admin-openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=admin
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_USER_PWD
export OS_AUTH_URL=http://$KEYSTONE_IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=$REGION
export OS_IMAGE_API_VERSION=2
EOF


cat << EOF | sudo tee ~/demo-openrc
export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=demo
export OS_TENANT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=$MEMBER_USER_PWD
export OS_AUTH_URL=http://$KEYSTONE_IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=$REGION
export OS_IMAGE_API_VERSION=2
EOF

echo "KEYSTONE CONFIGURATION END"

#Glance install and configuration
### Install Glance
echo "GLANCE INSTALL AND CONFIGURATION START"

# Create Glance database
mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $GLANCE_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $GLANCE_DB.* TO '$GLANCE_DBUSER'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $GLANCE_DB.* TO '$GLANCE_DBUSER'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"

source $ADMIN_RC_FILE

openstack user create --domain default --password $GLANCE_SVC_USER_PWD $GLANCE_SVC_USER
openstack role add --project $SERVICE_TENANT --user $GLANCE_SVC_USER $ADMIN_ROLE
openstack service create --name $GLANCE_SVC_NAME --description "OpenStack Image Service" image

openstack endpoint create --region $REGION image public http://$GLANCE_IP:9292
openstack endpoint create --region $REGION image internal http://$GLANCE_IP:9292
openstack endpoint create --region $REGION image admin http://$GLANCE_IP:9292

sudo apt-get install -y glance python-glanceclient

sudo service glance-api stop
sudo service glance-registry stop


# Configure Glance-API
sudo sed -i "s|#connection = <None>|connection = mysql+pymysql://$GLANCE_DBUSER:$GLANCE_DBPASS@$MYSQL_IP/$GLANCE_DB|g" /etc/glance/glance-api.conf
#sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$GLANCE_IP:5000\nauth_url = http://$GLANCE_IP:35357\nauth_plugin = password\nproject_domain_id = default\nuser_domain_id = default\nproject_name = $SERVICE_TENANT\nusername = $GLANCE_SVC_USER\npassword = $GLANCE_SVC_USER_PWD\n|g" /etc/glance/glance-api.conf

sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$GLANCE_IP:5000\nidentity_uri = http://$GLANCE_IP:35357\nadmin_tenant_name = $SERVICE_TENANT\nadmin_user = $GLANCE_SVC_USER\nadmin_password = $GLANCE_SVC_USER_PWD\n|g" /etc/glance/glance-api.conf

sudo sed -i "s|#flavor = <None>|flavor = $GLANCE_FLAVOR|g" /etc/glance/glance-api.conf
sudo sed -i "s|#default_store = file|default_store = file|g" /etc/glance/glance-api.conf
sudo sed -i "s|#filesystem_store_datadir = <None>|filesystem_store_datadir = /var/lib/glance/images/|g" /etc/glance/glance-api.conf
sudo sed -i "s|#notification_driver =|notification_driver = noop|g" /etc/glance/glance-api.conf
sudo sed -i "s|#verbose = true|verbose = true|g" /etc/glance/glance-api.conf


# Configure Glance-Registry
sudo sed -i "s|#connection = <None>|connection = mysql+pymysql://$GLANCE_DBUSER:$GLANCE_DBPASS@$MYSQL_IP/$GLANCE_DB|g" /etc/glance/glance-registry.conf

sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$GLANCE_IP:5000\nidentity_uri = http://$GLANCE_IP:35357\nadmin_tenant_name = $SERVICE_TENANT\nadmin_user = $GLANCE_SVC_USER\nadmin_password = $GLANCE_SVC_USER_PWD\n|g" /etc/glance/glance-registry.conf

#sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$GLANCE_IP:5000\nauth_url = http://$GLANCE_IP:35357\nauth_plugin = password\nproject_domain_id = default\nuser_domain_id = default\nproject_name = $SERVICE_TENANT\nusername = $GLANCE_SVC_USER\npassword = $GLANCE_SVC_USER_PWD\n|g" /etc/glance/glance-registry.conf
sudo sed -i "s|#flavor = <None>|flavor = $GLANCE_FLAVOR|g" /etc/glance/glance-registry.conf
sudo sed -i "s|#notification_driver =|notification_driver = noop|g" /etc/glance/glance-registry.conf
sudo sed -i "s|#verbose = true|verbose = true|g" /etc/glance/glance-registry.conf

sudo glance-manage db_sync
sleep 3

sudo service glance-registry start
sudo service glance-api start
echo "GLANCE INSTALL AND CONFIGURATION END"
sleep 5

### Nova
echo "NOVA INSTALL AND CONFIGURATION START"

# Create Nova database
mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $NOVA_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $NOVA_DB.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $NOVA_DB.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"

openstack user create --domain default --password $NOVA_SVC_USER_PWD $NOVA_SVC_USER
openstack role add --project $SERVICE_TENANT --user $NOVA_SVC_USER $ADMIN_ROLE
openstack service create --name $NOVA_SVC_NAME --description "OpenStack Compute Service" compute

openstack endpoint create --region $REGION compute public http://$NOVA_IP:8774/v2/%\(tenant_id\)s
openstack endpoint create --region $REGION compute internal http://$NOVA_IP:8774/v2/%\(tenant_id\)s
openstack endpoint create --region $REGION compute admin http://$NOVA_IP:8774/v2/%\(tenant_id\)s

sudo apt-get install -y nova-api nova-scheduler nova-conductor nova-cert nova-consoleauth nova-novncproxy python-novaclient
sudo apt-get install -y nova-compute sysfsutils

sudo service nova-api stop
sudo service nova-scheduler stop
sudo service nova-conductor stop
sudo service nova-cert stop
sudo service nova-consoleauth stop
sudo service nova-novncproxy stop

sudo rm /var/lib/nova/nova.sqlite

cat <<EOF | sudo tee -a /etc/nova/nova.conf
network_api_class=nova.network.neutronv2.api.API
security_group_api = neutron
verbose = True
firewall_driver=nova.virt.firewall.NoopFirewallDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
rpc_backend=rabbit
auth_strategy=keystone
my_ip=$MY_IP
enabled_apis=osapi_compute,metadata
novncproxy_base_url=http://$HORIZON_IP:6080/vnc_auto.html

[glance]
host = $GLANCE_IP

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[vnc]
enabled = true
vncserver_proxyclient_address = $MY_IP
vncserver_listen = 0.0.0.0
novncproxy_base_url=http://$HORIZON_IP:6080/vnc_auto.html

[database]
connection = mysql+pymysql://$NOVA_DBUSER:$NOVA_DBPASS@$MYSQL_IP/$NOVA_DB

[keystone_authtoken]
auth_uri = http://$KEYSTONE_IP:5000
#identity_uri = http://$KEYSTONE_IP:35357
#admin_tenant_name = $SERVICE_TENANT
#admin_user = $NOVA_SVC_USER
#admin_password = $NOVA_SVC_USER_PWD
auth_url = http://$KEYSTONE_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = $SERVICE_TENANT
username = $NOVA_SVC_USER
password = $NOVA_SVC_USER_PWD

[oslo_messaging_rabbit]
rabbit_host = $MY_IP
rabbit_userid = $RABBIT_USER
rabbit_password = $RABBIT_PWD

[libvirt]
virt_type = qemu
EOF

sudo nova-manage db sync

sudo service nova-api start
sudo service nova-scheduler start
sudo service nova-conductor start
sudo service nova-cert start
sudo service nova-consoleauth start
sudo service nova-novncproxy start

sudo service nova-compute restart
echo "NOVA INSTALL AND CONFIGURATION END"
sleep 4

### Neutron
echo "NEUTRON INSTALL AND CONFIGURATION START"

#Create Neutron database
mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $NEUTRON_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $NEUTRON_DB.* TO '$NEUTRON_DBUSER'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $NEUTRON_DB.* TO '$NEUTRON_DBUSER'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"

openstack user create --domain default --password $NEUTRON_SVC_USER_PWD $NEUTRON_SVC_USER
openstack role add --project $SERVICE_TENANT --user $NEUTRON_SVC_USER $ADMIN_ROLE
openstack service create --name $NEUTRON_SVC_NAME --description "OpenStack Networking" network
openstack endpoint create --region $REGION network public http://$NEUTRON_IP:9696
openstack endpoint create --region $REGION network internal http://$NEUTRON_IP:9696
openstack endpoint create --region $REGION network admin http://$NEUTRON_IP:9696

sudo apt-get install -y neutron-server neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent python-neutronclient

sudo service neutron-server stop


# Configure Neutron
sudo sed -i "s|connection = sqlite:////var/lib/neutron/neutron.sqlite|connection = mysql+pymysql://$NEUTRON_DBUSER:$NEUTRON_DBPASS@$MYSQL_IP/$NEUTRON_DB|g" /etc/neutron/neutron.conf

sudo sed -i 's/# service_plugins =/service_plugins = router/g' /etc/neutron/neutron.conf
sudo sed -i 's/# allow_overlapping_ips = False/allow_overlapping_ips = True/g' /etc/neutron/neutron.conf

sudo sed -i "s|# rpc_backend=rabbit|rpc_backend=rabbit|g" /etc/neutron/neutron.conf
sudo sed -i "s|oslo_messaging_rabbit]|oslo_messaging_rabbit]\nrabbit_host=$RABBITMQ_IP\nrabbit_userid = $RABBIT_USER\nrabbit_password = $RABBIT_PWD\n|g" /etc/neutron/neutron.conf
sudo sed -i 's/# auth_strategy = keystone/auth_strategy = keystone/g' /etc/neutron/neutron.conf

sudo sed -i "s|auth_uri = http:|#auth_uri = http:|g" /etc/neutron/neutron.conf
#sudo sed -i "s|identity_uri = http:|#identity_uri = http:|g" /etc/neutron/neutron.conf
#sudo sed -i "s|admin_tenant_name = %|#admin_tenant_name = %|g" /etc/neutron/neutron.conf
#sudo sed -i "s|admin_user = %|#admin_user = %|g" /etc/neutron/neutron.conf
#sudo sed -i "s|admin_password = %|#admin_password = %|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\npassword = $NEUTRON_SVC_USER_PWD|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nusername = $NEUTRON_SVC_USER|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nproject_name = $SERVICE_TENANT|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nuser_domain_id = default|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nproject_domain_id = default|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_plugin = password|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_url = http://$NEUTRON_IP:35357|g" /etc/neutron/neutron.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$NEUTRON_IP:5000|g" /etc/neutron/neutron.conf

sudo sed -i "s/# notify_nova_on_port_status_changes = True/notify_nova_on_port_status_changes = True/g" /etc/neutron/neutron.conf
sudo sed -i "s/# notify_nova_on_port_data_changes = True/notify_nova_on_port_data_changes = True/g" /etc/neutron/neutron.conf
sudo sed -i "s|# nova_url = http://127.0.0.1:8774|nova_url = http://$NOVA_IP:8774|g" /etc/neutron/neutron.conf

sudo sed -i "s|nova]|nova]\npassword = $NOVA_SVC_USER_PWD|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nusername = $NOVA_SVC_USER|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nproject_name = $SERVICE_TENANT|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nregion_name = $REGION|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nuser_domain_id = default|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nproject_domain_id = default|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nauth_plugin = password|g" /etc/neutron/neutron.conf
sudo sed -i "s|nova]|nova]\nauth_url = http://$NOVA_IP:35357|g" /etc/neutron/neutron.conf

sudo sed -i "s|# verbose = False|verbose = True|g" /etc/neutron/neutron.conf

# Configure Neutron ML2
sudo sed -i 's|# type_drivers = local,flat,vlan,gre,vxlan,geneve|type_drivers = flat,gre|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# tenant_network_types = local|tenant_network_types = flat,gre|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# mechanism_drivers =|mechanism_drivers = openvswitch,l2population|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# tunnel_id_ranges =|tunnel_id_ranges = 1:1000|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# extension_drivers =|extension_drivers = port_security|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# flat_networks =|flat_networks = public|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# vni_ranges =|vni_ranges = 1:1000|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# enable_ipset = True|enable_ipset = True|g' /etc/neutron/plugins/ml2/ml2_conf.ini
#Configure metadata_agent.ini
sudo sed -i 's|auth_url = http://localhost:5000/v2.0|auth_url = http://'$MY_IP':35357|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|auth_region = RegionOne|auth_region = '$REGION'|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|# nova_metadata_ip = 127.0.0.1|nova_metadata_ip = '$MY_IP'|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|# metadata_proxy_shared_secret =|metadata_proxy_shared_secret = openstack|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nauth_uri = http://'$MY_IP':5000|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nauth_plugin = password|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nproject_domain_id = default|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nuser_domain_id = default|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nproject_name = '$SERVICE_TENANT'|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nusername = '$NEUTRON_SVC_USER'|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\npassword = '$NEUTRON_SVC_USER_PWD'|g' /etc/neutron/metadata_agent.ini
sudo sed -i 's|DEFAULT]|DEFAULT]\nverbose = True|g' /etc/neutron/metadata_agent.ini
#configure l3_agent.ini
sudo sed -i 's|# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver|interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver|g' /etc/neutron/l3_agent.ini
#configure dhcp_agent.ini
sudo sed -i 's|# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver|interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver|g' /etc/neutron/dhcp_agent.ini

#Configure /etc/neutron/plugins/ml2/openvswitch_agent.ini
sudo sed -i 's|ovs]|ovs]\nintegration_bridge = br-int\ntunnel_bridge = br-tun\nlocal_ip = '$MY_IP'|g' /etc/neutron/plugins/ml2/openvswitch_agent.ini
sudo sed -i "0,/agent]/s//agent]\ntunnel_types = gre/" /etc/neutron/plugins/ml2/openvswitch_agent.ini

cat <<EOF | sudo tee -a /etc/nova/nova.conf
[neutron]
url = http://$NEUTRON_IP:9696
auth_url = http://$NEUTRON_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = $REGION
project_name = $SERVICE_TENANT
username = $NEUTRON_SVC_USER
password = $NEUTRON_SVC_USER_PWD
service_metadata_proxy = True
metadata_proxy_shared_secret = openstack
EOF

sudo rm -f /var/lib/neutron/neutron.sqlite

#populate the neutron database
#su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
sudo neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

sudo service nova-api restart
sudo service nova-scheduler restart
sudo service nova-conductor restart

sudo service neutron-server restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-plugin-openvswitch-agent restart

echo "NEUTRON INSTALL AND CONFIGURATION END"
sleep 5

echo "BEGIN HEAT INSTALL"

#Create heat database
mysql -u root -p$MYSQL_PWD -e "CREATE DATABASE $HEAT_DB;"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $HEAT_DB.* TO '$HEAT_DBUSER'@'localhost' IDENTIFIED BY '$HEAT_DBPASS';"
mysql -u root -p$MYSQL_PWD -e "GRANT ALL ON $HEAT_DB.* TO '$HEAT_DBUSER'@'%' IDENTIFIED BY '$HEAT_DBPASS';"

openstack user create --domain default --password $HEAT_ADMIN_PWD $HEAT_ADMIN_USER
openstack role add --project $SERVICE_TENANT --user $HEAT_ADMIN_USER $ADMIN_ROLE
openstack service create --name $HEAT_SVC_NAME --description "Orchestration" orchestration
openstack service create --name $HEAT_CFN_SVC_NAME --description "Orchestration" cloudformation
openstack endpoint create --region $REGION orchestration public http://$HEAT_IP:8004/v1/%\(tenant_id\)s
openstack endpoint create --region $REGION orchestration internal http://$HEAT_IP:8004/v1/%\(tenant_id\)s
openstack endpoint create --region $REGION orchestration admin http://$HEAT_IP:8004/v1/%\(tenant_id\)s
openstack endpoint create --region $REGION cloudformation public http://$HEAT_IP:8000/v1
openstack endpoint create --region $REGION cloudformation internal http://$HEAT_IP:8000/v1
openstack endpoint create --region $REGION cloudformation admin http://$HEAT_IP:8000/v1
openstack domain create --description "Stack projects and users" heat
openstack user create --domain heat --password $HEAT_DOMAIN_ADMIN_PWD $HEAT_DOMAIN_ADMIN
openstack role add --domain heat --user $HEAT_DOMAIN_ADMIN $ADMIN_ROLE
openstack role create heat_stack_owner
openstack role add --project demo --user demo heat_stack_owner
openstack role create heat_stack_user

#install orchestration module
sudo apt-get install -y heat-api heat-api-cfn heat-engine python-heatclient
sleep 5

cat << EOF | sudo tee -a /etc/heat/heat.conf
[trustee]
auth_uri = http://$KEYSTONE_IP:5000
auth_url = http://$KEYSTONE_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = $SERVICE_TENANT
username = $HEAT_SVC_USER
password = $HEAT_SVC_USER_PWD

[clients_keystone]
auth_uri = http://$KEYSTONE_IP:5000

[ec2authtoken]
auth_uri = http://$KEYSTONE_IP:5000
EOF

sudo sed -i "s|#rpc_backend = rabbit|rpc_backend = rabbit|g" /etc/heat/heat.conf
sudo sed -i "s|#verbose = true|verbose = true|g" /etc/heat/heat.conf
sudo sed -i "s|verbose = true|verbose = true\nstack_user_domain_name = heat|g" /etc/heat/heat.conf
sudo sed -i "s|verbose = true|verbose = true\nstack_domain_admin_password = $HEAT_DOMAIN_ADMIN_PWD|g" /etc/heat/heat.conf
sudo sed -i "s|verbose = true|verbose = true\nstack_domain_admin = $HEAT_DOMAIN_ADMIN|g" /etc/heat/heat.conf
sudo sed -i "s|verbose = true|verbose = true\nheat_metadata_server_url = http://$HEAT_IP:8000|g" /etc/heat/heat.conf
sudo sed -i "s|verbose = true|verbose = true\nheat_waitcondition_server_url = http://$HEAT_IP:8000/v1/waitcondition|g" /etc/heat/heat.conf

sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_uri = http://$HEAT_IP:5000|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_url = http://$HEAT_IP:35357|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nauth_plugin = password|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nproject_domain_id = default|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nuser_domain_id = default|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nproject_name = $SERVICE_TENANT|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\nusername = $HEAT_SVC_USER|g" /etc/heat/heat.conf
sudo sed -i "s|keystone_authtoken]|keystone_authtoken]\npassword = $HEAT_SVC_USER_PWD|g" /etc/heat/heat.conf

sudo sed -i "s|oslo_messaging_rabbit]|oslo_messaging_rabbit]\nrabbit_host = $HEAT_IP|g" /etc/heat/heat.conf
sudo sed -i "s|oslo_messaging_rabbit]|oslo_messaging_rabbit]\nrabbit_userid = $RABBIT_USER|g" /etc/heat/heat.conf
sudo sed -i "s|oslo_messaging_rabbit]|oslo_messaging_rabbit]\nrabbit_password = $RABBIT_PWD|g" /etc/heat/heat.conf

sudo sed -i "s|database]|database]\nconnection = mysql://$HEAT_DBUSER:$HEAT_DBPASS@$MYSQL_IP/$HEAT_DB|g" /etc/heat/heat.conf

#Delete the heat.sqlite file that is created by default
sudo rm /var/lib/heat/heat.sqlite

#Create the hest service tables
sudo heat-manage db_sync

sudo service heat-api restart
sudo service heat-api-cfn restart
sudo service heat-engine restart
echo "END HEAT INSTALL"


#Install Horizon
echo "HORIZON INSTALL AND CONFIGURATION START"
sudo apt-get install -y openstack-dashboard

sudo sed -i "s|OPENSTACK_HOST = \"127.0.0.1\"|OPENSTACK_HOST = \"$MY_IP\"|g" /etc/openstack-dashboard/local_settings.py
#sudo sed -i "s|ALLOWED_HOSTS = '*'|ALLOWED_HOSTS = ['*', ]|g" /etc/openstack-dashboard/local_settings.py
sudo sed -i "s|OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"_member_\"|OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"|g" /etc/openstack-dashboard/local_settings.py

sudo service apache2 restart
echo "HORIZON INSTALL AND CONFIGURATION END"
sleep 5
sudo service nova-api restart
sudo service nova-scheduler restart
sudo service nova-conductor restart
sudo service nova-cert start
sudo service nova-consoleauth restart
sudo service nova-novncproxy restart
sudo service nova-compute restart
sudo service neutron-server restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-plugin-openvswitch-agent restart
