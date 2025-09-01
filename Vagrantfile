Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_version = "202508.03.0"

  config.vm.hostname = "DevOps"
  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "DevOps"
    vb.cpus   = 8
    vb.memory = 16384
  end

  config.vm.provision "shell", path: "boot.sh"
end
