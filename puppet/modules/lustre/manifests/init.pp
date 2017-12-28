class lustre::client::base {
  package {'epel-release': }
  
  yumrepo { 'lustre-client':
      ensure   => present,
      baseurl  => 'https://downloads.hpdd.intel.com/public/lustre/latest-release/el7/client',
      descr    => 'lustre-client',
      gpgcheck => 0,
      enabled  => 1,
  }
  
  package { 'kmod-lustre-client': 
    require => Yumrepo['lustre-client'],
  }
  package { 'lustre-client': 
    require => Yumrepo['lustre-client'],
  }
  package { 'lustre-client-dkms': 
    require => Yumrepo['lustre-client'],
  }
}

class lustre::server::base {
  package {'epel-release': }
  
  yumrepo { 'lustre-server':
      ensure   => present,
      baseurl  => 'https://downloads.hpdd.intel.com/public/lustre/latest-release/el7/patchless-ldiskfs-server',
      descr    => 'lustre-server',
      gpgcheck => 0,
      enabled  => 1,
  }
  
  yumrepo { 'e2fsprogs-wc':
      ensure   => present,
      baseurl  => 'https://downloads.hpdd.intel.com/public/e2fsprogs/latest/el7',
      descr    => 'e2fsprogs-wc',
      gpgcheck => 0,
      enabled  => 1,
  }
  
  package { 'kmod-lustre': 
    require => Yumrepo['lustre-server'],
  } 
  package { 'kmod-lustre-osd-ldiskfs': 
    require => Yumrepo['lustre-server'],
  }
  package { 'lustre': 
    require => Yumrepo['lustre-server'],
  } 
  package { 'e2fsprogs': 
    require => Yumrepo['e2fsprogs-wc'],
  }
  package { 'lustre-tests': 
    require => Yumrepo['lustre-server'],
  }
  package { 'lustre-osd-ldiskfs-mount': 
    require => Yumrepo['lustre-server'],
  }
  
  kmod::load { 'lnet':
    require => Package['lustre'],
  }
  exec { 'lnet_configure':
    command => '/usr/sbin/lnetctl lnet configure',
    unless  => '/usr/sbin/lnetctl net show > /dev/null 2>&1',
    require => Kmod::Load['lnet'],
  }
  exec { 'lnet_tcp1': 
    command => '/usr/sbin/lnetctl net add --net tcp1 --if eth1',
    unless  => '/usr/sbin/lnetctl net show | grep -q tcp1 > /dev/null 2>&1',
    require => Exec['lnet_configure'],
  }
  
}

class lustre::server::mgs {
  class { 'lustre::server::base': } 
  
  exec {'mkfs_lustre_mgs':
    command => '/usr/sbin/mkfs.lustre --mgs --fsname=lfsv /dev/sdb',
    unless  => '/sbin/blkid -s TYPE /dev/sdb | grep -q ext4',
    require => Class['lustre::server::base'],
  }
  file { '/mgs':
    ensure => directory,
  }
  mount {'/mgs':
    ensure => mounted,
    device => '/dev/sdb',
    fstype => 'lustre',
    require => Exec['mkfs_lustre_mgs'],
  }
  
  exec {'mkfs_lustre_mds':
    command => '/usr/sbin/mkfs.lustre --mdt --fsname=lfsv --mgsnode=10.73.10.11@tcp1 --index=0 /dev/sdc',
    unless  => '/sbin/blkid -s TYPE /dev/sdc | grep -q ext4',
    require => Class['lustre::server::base'],
  }
  file { '/mds':
    ensure => directory,
  }
  mount {'/mds':
    ensure => mounted,
    device => '/dev/sdc',
    fstype => 'lustre',
    require => Exec['mkfs_lustre_mds'],
  }
  
}

class lustre::server::oss {
  class { 'lustre::server::base': }
  
  $ost_devices = $facts['disks'].keys.filter |$v| {$v != "sda"}
  $ost_devices.each |Integer $index, String $device| {
    exec { "mkfs_lustre_oss_${device}":
      command => "/usr/sbin/mkfs.lustre --fsname=lfsv --mgsnode=10.73.10.11@tcp1 --ost --index=${index} /dev/${device}",
      unless  => "/sbin/blkid -s TYPE /dev/${device} | grep -q ext4",
      require => Class['lustre::server::base'],
    }
    file {"/oss${index}":
      ensure => directory,
    }
    mount {"/oss${index}":
      ensure => mounted,
      device => "/dev/${device}",
      fstype => 'lustre',
      require => Exec["mkfs_lustre_oss_${device}"],
    }
  }
}

class lustre::client::mount {
  class { 'lustre::client::base': }
  
  file {'/mnt/lustre':
    ensure => directory,
  }
  mount {'/mnt/lustre':
    ensure => mounted,
    device => "10.73.10.11@tcp1:/lfsv",
    fstype => 'lustre',
    require => Class["lustre::client::base"],
  }
}
