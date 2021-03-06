Vagrant.configure("2") do |config|
	
	#https://github.com/voxpupuli/vagrant-librarian-puppet
	config.librarian_puppet.puppetfile_dir = "puppet"
	config.librarian_puppet.destructive = false

	# Set the default RAM allocation for each VM.
	# 1GB is sufficient for demo and training purposes.
	# Admin and builder servers are allocated 2GB and 4GB RAM
	# respectively. Refer to the VM definitions to change.
	config.vm.provider "virtualbox" do |vbx|
		vbx.memory = 1024
	end

	# Directory root for additional vdisks for MGT, MDT0, and OSTs
	vdisk_root = "#{ENV['HOME']}/VirtualBox\ VMs/vdisks"
	# Number of shared disk devices per OSS server pair
	sdnum=8
	# Use pre-built box from CentOS project
	config.vm.box = "centos/7"

	# Hostname prefix for the cluster nodes
	# Example conventions:
	# ct<vmax><vmin>: CentOS <vmax>.<vmin>, e.g. ct73 = CentOS 7.3
	# rh<vmax><vmin>: RHEL <vmax>.<vmin>, e.g. rh73 = RHEL 7.3
	# el<vmax><vmin>: Generic RHEL derivative <vmax>.<vmin>,
	# 	e.g. el73 = RHEL/CentOS 7.3
	# el<vmax>: Generic RHEL derivative <vmax>, e.g. el7 = RHEL/CentOS 7.x
	# sl<vmax><vmin>: SLES <vmax> SP<vmin>, e.g. sl121 = SLES 12 sp1
	# ub<vmax><vmin>: Ubuntu <vmax>.<vmin>, e.g. ub1604 = Ubuntu 16.04
	#
	# Each host in the virtual cluster will be automatically assigned 
	# a name based on the prefix and the function of the host
	# The following examples are nodes running CentOS 7.3:
	# ct73-mds1 = 1st metadata server
	# ct73-oss3 = 3rd OSS
	# ct73-c2 = 2nd compute node
	host_prefix="ct7"
	# Create a set of /24 networks under a single /16 subnet range
	subnet_prefix="10.73"
	# Management network for admin comms
	mgmt_net_pfx="#{subnet_prefix}.10"

	# Create a basic hosts file for the VMs.
	open('hosts', 'w') { |f|
	f.puts <<-__EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

#{mgmt_net_pfx}.9 #{host_prefix}-b.lfs.local #{host_prefix}-b
#{mgmt_net_pfx}.11 #{host_prefix}-mds1.lfs.local #{host_prefix}-mds1
#{mgmt_net_pfx}.21 #{host_prefix}-oss1.lfs.local #{host_prefix}-oss1
#{mgmt_net_pfx}.22 #{host_prefix}-oss2.lfs.local #{host_prefix}-oss2
__EOF
	(1..1).each do |cidx|
		f.puts "#{mgmt_net_pfx}.3#{cidx} #{host_prefix}-c#{cidx}.lfs.local #{host_prefix}-c#{cidx}\n"
	end
	}
	config.vm.provision "shell", inline: "cp -f /vagrant/hosts /etc/hosts"
	config.vm.provision "shell", inline: "setenforce 0; cat >/etc/selinux/config<<__EOF
SELINUX=disabled
SELINUXTYPE=targeted
__EOF"

	# A simple way to create a key that can be used to enable
	# SSH between the virtual guests.
	#
	# The private key is copied onto the root account of the 
	# administration node and the public key is appended to the
	# authorized_keys file of the root account for all nodes
	# in the cluster.
	#
	# Shelling out may not be the most Vagrant-friendly means to
	# create this key but it avoids more complex methods such as
	# developing a plugin.
	#
	# Popen may be a more secure way to exec but is more code
	# for what is, in this case, a relatively small gain.
	if not(File.exist?("id_rsa"))
		res = system("ssh-keygen -t rsa -N '' -f id_rsa")
	end

	# Add the generated SSH public key to each host's
	# authorized_keys file.
	config.vm.provision "shell", inline: "mkdir -m 0700 -p /root/.ssh; [ -f /vagrant/id_rsa.pub ] && (awk -v pk=\"`cat /vagrant/id_rsa.pub`\" 'BEGIN{split(pk,s,\" \")} $2 == s[2] {m=1;exit}END{if (m==0)print pk}' /root/.ssh/authorized_keys )>> /root/.ssh/authorized_keys; chmod 0600 /root/.ssh/authorized_keys"

	config.vm.provision "shell", inline: <<-SHELL
    # Installing puppet client
    sudo rpm -Uvh https://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm
    yum -y install puppet-agent-1.5.2-1.el7
    # https://bugzilla.redhat.com/show_bug.cgi?id=1483888
    sed -i '311s/| "umask_override" | "use_pty"/| "umask_override" | "use_pty" | "match_group_by_gid"/' /opt/puppetlabs/puppet/share/augeas/lenses/dist/sudoers.aug

    # Installing yum-plugin-priorities for puppet to work properly
    yum -y install yum-plugin-priorities

    # Installing epel-release
    yum -y install epel-release
    yum -y upgrade ca-certificates --disablerepo=epel
  SHELL

	#
	# Create the metadata server
	#
	(1..1).each do |mds_idx|
		config.vm.define "mds#{mds_idx}" do |mds|
			# Create additional storage to be shared between
			# the metadata server VMs.
			# Storage services associated with these #{vdisk_root}
			# will be maintained using HA failover.
			mds.vm.provider "virtualbox" do |vbx|
				if mds_idx==1 && not(File.exist?("#{vdisk_root}/mgs.vdi"))
					vbx.customize ["createmedium", "disk",
						"--filename", "#{vdisk_root}/mgs.vdi",
						"--size", "512",
						"--format", "VDI",
						"--variant", "fixed"]
				end
				if mds_idx==1 && not(File.exist?("#{vdisk_root}/mdt0.vdi"))
                			vbx.customize ["createmedium", "disk",
						"--filename", "#{vdisk_root}/mdt0.vdi",
						"--size", "5120",
						"--format", "VDI",
						"--variant", "fixed"]
				end
				# Add a storage controller to each VM.
				# SATA chosen because when VM is booted, disks attached
				# to SAS and SCSI don't show up in /dev/disk/by-id.
				# Appears to be a bug / limitation in VBox.
				#
				# Primitive check to see whether or not the
				# storage has been provisioned previously.
				# Needed because the vbx.customize...storagectl
				# command is not idempotent and will fail if the
				# controller has been created already.
				#
				# Also, cannot catch the exception that gets
				# raised, as it is handled by thed
				# VirtualBox.customize method itself. 
				#
				# Cannot suppress error or continue if exception
				# is raised. No workarounds that would be portable
				# or easy to maintain.
				# 
				# Does not seem to affect storageattach. 
				if not(File.exist?("#{vdisk_root}/mgs.vdi"))
					vbx.customize ["storagectl", :id,
						"--name", "SATAController",
						"--add", "sata"]
				end
				vbx.customize ["storageattach", :id,
					"--storagectl", "SATAController",
					"--port", "0",
					"--type", "hdd",
					"--medium", "#{vdisk_root}/mgs.vdi",
					"--mtype", "shareable",
					"--device", "0"]
				vbx.customize ["storageattach", :id,
					"--storagectl", "SATAController",
					"--port", "1",
					"--type", "hdd",
					"--medium", "#{vdisk_root}/mdt0.vdi",
					"--mtype", "shareable",
					"--device", "0"]
			end
			# Set host name of VM
			mds.vm.host_name = "#{host_prefix}-mds#{mds_idx}.lfs.local"
			# Admin / management network
			mds.vm.network "private_network",
				ip: "#{mgmt_net_pfx}.1#{mds_idx}",
				netmask: "255.255.255.0"

			mds.vm.provision "puppet" do |puppet|
				puppet.manifests_path = "./puppet/manifests"
				puppet.manifest_file = "mds.pp"
				puppet.module_path = [ "puppet/modules" ]
				puppet.options = "--verbose --debug"
			end
		end
	end

	#
	# Create the object storage servers (OSS)
	# Servers are configured in HA pairs
	# By default, only the first 2 nodes are created
	# To instantiate oss3 and oss4, use this command:
	# 	vagrant up oss{3,4}
	#
	(1..2).each do |oss_idx|
		config.vm.define "oss#{oss_idx}",
			autostart: (oss_idx>2 ? false : true) do |oss|

			# Create additional storage to be shared between
			# the object storage server VMs.
			# Storage services associated with these #{vdisk_root}
			# will be maintained using HA failover.
			oss.vm.provider "virtualbox" do |vbx|
				# Set the OST index range based on the node number.
				# Each OSS is one of a pair, and will share these devices
				# Equation assumes that OSSs are allocated in pairs with
				# consecutive numbering. Each pair of servers has a set
				# of shared virtual disks (vdisks) numbered in the range
				# osd_min to osd_max. e.g.:
				# oss{1,2} share OST0..OST7 and oss{3,4} share OST8..OST16, 
				# assuming the number of disks per pair (sdnum) is 8
				osd_min = ((oss_idx-1) / 2) * sdnum
				osd_max = osd_min + 7
				# Create the virtual disks for the OSTs
				# Only create the vdisks on odd-numbered VMs
				# (node 1 in each HA pair)
				if oss_idx % 2 == 1
					(osd_min..osd_max).each do |ost|
				 		if not(File.exist?("#{vdisk_root}/ost#{ost}.vdi"))
							vbx.customize ["createmedium", "disk",
								"--filename", "#{vdisk_root}/ost#{ost}.vdi",
								"--size", "5120",
								"--format", "VDI",
								"--variant", "fixed"
								]
						end
					end
				end
				# Add a storage controller to each VM.
				# SATA chosen because when VM is booted, disks attached
				# to SAS and SCSI don't show up in /dev/disk/by-id.
				# Appears to be a bug / limitation in VBox.
				#
				# Primitive check to see whether or not the
				# storage has been provisioned previously.
				# Needed because the vbx.customize...storagectl
				# command is not idempotent and will fail if the
				# controller has been created already.
				if not(File.exist?("#{vdisk_root}/ost#{osd_min}.vdi"))
					vbx.customize ["storagectl", :id,
						"--name", "SATAController",
						"--add", "sata"
						]
				end

				# Attach the vdisks to each OSS in the pair
				(osd_min..osd_max).each do |osd|
					pnum = osd % sdnum
					vbx.customize ["storageattach", :id,
						"--storagectl", "SATAController",
						"--port", "#{pnum}",
						"--type", "hdd",
						"--medium", "#{vdisk_root}/ost#{osd}.vdi",
						"--mtype", "shareable",
						"--comment","%sOST%04d" % [host_prefix.upcase, osd]
						]
				end
			end

			oss.vm.host_name = "#{host_prefix}-oss#{oss_idx}.lfs.local"
			# Admin / management network
			oss.vm.network "private_network",
				ip: "#{mgmt_net_pfx}.2#{oss_idx}",
				netmask: "255.255.255.0"
				
			oss.vm.provision "puppet" do |puppet|
				puppet.manifests_path = "./puppet/manifests"
				puppet.manifest_file = "oss.pp"
				puppet.module_path = [ "puppet/modules" ]
				puppet.options = "--verbose --debug"
			end
		end
	end

	# Create a set of compute nodes.
	# By default, only 2 compute nodes are created.
	# The configuration supports a maximum of 8 compute nodes.
	(1..1).each do |c_idx|
		config.vm.define "c#{c_idx}",
			autostart: (c_idx>2 ? false : true) do |c|
			c.vm.host_name = "#{host_prefix}-c#{c_idx}.lfs.local"
			# Admin / management network
			c.vm.network "private_network",
				ip: "#{mgmt_net_pfx}.3#{c_idx}",
				netmask: "255.255.255.0"
				
			c.vm.provision "puppet" do |puppet|
				puppet.manifests_path = "./puppet/manifests"
				puppet.manifest_file = "client.pp"
				puppet.module_path = [ "puppet/modules" ]
				puppet.options = "--verbose --debug"
			end
		end
	end
end
