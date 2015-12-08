sudo apt-get update
echo "apt-get update done....."
sleep 3
sudo apt-get install -y openssh-server

sudo apt-get install -y git
#git clone https://github.com/metral/restore_networking.git
#cd restore_networking/
#./restore_networking.sh
#sleep 3

sudo apt-get install -y ntp
sudo ntpdate –u 0.us.pool.ntp.org
sleep 3

#wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.13.1-trusty/linux-headers-3.13.1-031301-generic_3.13.1-031301.201401291035_amd64.deb
#wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.13.1-trusty/linux-headers-3.13.1-031301_3.13.1-031301.201401291035_all.deb
#wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.13.1-trusty/linux-image-3.13.1-031301-generic_3.13.1-031301.201401291035_amd64.deb
#sudo dpkg -i linux-headers*.deb linux-image-3.13.1-031301-generic_3.13.1-031301.201401291035_amd64.deb
#sleep 3

#sudo apt-get install –y ubuntu-cloud-keyring python-software-properties
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y cloud-archive:liberty

sudo apt-get -y update
sudo apt-get -y dist-upgrade
sudo reboot

