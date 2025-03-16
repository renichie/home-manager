################## misc #######################################
alias grep='grep --color=always'
alias hgrep='history | grep'
alias hg='history | grep'
alias reload='source ~/.bashrc'

################## GIT #######################################
alias g='git'
alias got='git'
alias gut='git'
alias gst='git status'
alias ga='git add'
alias gca='git commit --amend'
alias gcane='git commit --amend --no-edit'
alias gfa='git fetch --all'
alias glg='git lg1 --all'

################## TMUX #######################################
alias tats='tmux attach-session -t'
alias ta='tats'
alias tshared='tmux -S /var/tmux/socket attach'


#navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias ll='ls -lash'

#terminal view
alias hs='history'

#password generation
generate_password()	{ date +%s | sha256sum | base64 | head -c 32 ; echo; }

################## docker ################################
#dpsf()		{ docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.ID}}\t{{.Image}}\t{{.Ports}}'; } #formatted version
#dps()		{ docker ps $@ --format 'table {{.Names}}\t{{.Status}}\t{{.ID}}\t{{.Ports}}'; } #formatted version #2
#dpss()		{ docker ps $@ --format 'table {{.Names}}\t{{.Status}}\t{{.ID}}'; } #short formatted version
#dpsp()		{ docker ps $@ --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; } #short formatted version
#dpsl()		{ docker ps $@ --format 'table {{.Names}}\t{{.Status}}\t{{.ID}}\t{{.Image}}\t{{.Ports}}'; } #formatted version #1
#dbash() 	{ docker cp ~/.bashrc $1:/etc/bash.bashrc; docker exec -ti $1 bash; } 	#copies the user bashrc into the container and opens a shell in it
#dbr()		{ docker exec -ti -u root $1 bash; }
#dkrm()		{ docker stop $1; docker rm $1; }
#dimn()		{ docker images $@ --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}'; }
#dcrm()		{ docker stop $1 ; docker rm $1; }
#dcDelWar()	{ docker exec -t -u root $1 rm -rf /opt/ol/wlp/usr/servers/defaultServer/dropins/expanded; docker restart $1; }
#dhf()		{ docker history --format 'table {{.ID}}\t{{.CreatedAt}}\t{{.CreatedBy}}' $@; }
#dpsql()		{ docker exec -ti $1 psql -U postgres;}

################################## misc #####################################
