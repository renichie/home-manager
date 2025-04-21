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

### Granting `/dev/uinput` Access for Xremap on Manjaro

Xremap needs write access to `/dev/uinput` in order to inject synthetic key events under Wayland. By default on Manjaro this device is owned by `root:root` with mode `600`. The steps below will:

1. Ensure you’re in an `input` group  
2. Create a udev rule to set the correct group and permissions  
3. Reload udev rules and the `uinput` module so the rule takes effect  
4. Verify the new permissions  
5. Restart Xremap

---

1. Ensure the `input` group exists & add yourself

```bash
# If “input” doesn’t exist, create it:
sudo groupadd input

# Add your user to it:
sudo gpasswd -a $USER input

# Log out and back in for group membership to take effect
```

2. Create the udev rule

Create /etc/udev/rules.d/99-uinput.rules with:
```
 /etc/udev/rules.d/99-uinput.rules
KERNEL=="uinput", MODE="0660", GROUP="input"
```

Or drop it via:

```
sudo tee /etc/udev/rules.d/99-uinput.rules <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input"
EOF
```

3. Reload udev rules & the kernel module

 Reload udev’s rule database
```
sudo udevadm control --reload-rules
```

Unload and reload the uinput module so the new rule is applied
```
sudo rmmod uinput
sudo modprobe uinput
```

 (Optional) Re-trigger the device if needed
 ```
sudo udevadm trigger --action=add --attr-match=KERNEL=uinput
```

4. Verify /dev/uinput permissions

```
ls -l /dev/uinput
```
Expect:
```
# crw-rw---- 1 root input 10, 223 Apr 21 09:24 /dev/uinput
```

5. Restart Xremap

Ensure the uinput module is loaded
```
sudo modprobe uinput
```

Reload your user‑unit definitions
```
systemctl --user daemon-reload
```

Restart and check xremap

```
systemctl --user restart xremap.service
systemctl --user status  xremap.service
```
