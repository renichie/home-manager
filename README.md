# Homemanager Setup

Homemanager setup for personal use.

Feel free to use as you like :)

## Installation

### 
```shell
sh <(curl -L https://nixos.org/nix/install) --daemon
```

```shell
nix-shell -p home-manager
home-manager init
```

```shell
sudo echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
```
or if that fails:
```shell
su
echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
```

 ```shell
 mkdir -p ~/.config/
 cd ~/.config
 git clone https://github.com/renichie/home-manager.git
 cd ~/.config/home-manager
 # first time execution! -- replace with hostname flake
 home-manager switch --flake .#HERA -b bckp 
 # subsequent updates
 hm_switch
 ```
