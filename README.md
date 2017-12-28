# Lustre Vagrant

Vagrant environment for deploying a small lustre cluster and clients.  The vagrant file is based on the work done [here](http://wiki.lustre.org/Create_a_Virtual_HPC_Storage_Cluster_with_Vagrant).  Puppet modules were added to auto deploy lustre software packages and initialize a lustre filesystem.

## Vagrant Plugins Required

1. vagrant-librarian-puppet
2. vagrant-share
3. vagrant-vbguest

## Deploy

```
vagrant up mgs1
vagrant up oss1
vagrant up c1
```

The lustre filesystem is mounted on `c1` at `/mnt/lustre`
