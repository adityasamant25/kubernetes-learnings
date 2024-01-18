alias k=kubectl
alias kn='kubectl config set-context --current --namespace '
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"

source <(kubectl completion bash) # set up autocomplete in bash into the current shell, bash-completion package should be installed first.
echo "source <(kubectl completion bash)" >> ~/.bashrc # add autocomplete permanently to your bash shell.

complete -o default -F __start_kubectl k