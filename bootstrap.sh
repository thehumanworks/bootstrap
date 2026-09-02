#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
environment="${1:-dev}"

configure_ssh() {
	if [[ $(uname -s) != Linux ]]; then
		if [[ $environment == "--configure-ssh" ]]; then
			echo "OpenSSH image configuration is only supported on Linux" >&2
			exit 1
		fi
		return
	fi

	if [[ ! -x /usr/sbin/sshd ]]; then
		echo "openssh-server was not installed by the dev bootstrap" >&2
		exit 1
	fi

	install -d -m 0700 /root/.ssh
	install -m 0600 "$repo_dir/ssh/id_ed25519.pub" /root/.ssh/authorized_keys

	install -d -m 0755 /etc/ssh/sshd_config.d
	install -m 0644 /dev/null /etc/ssh/sshd_config.d/99-bootstrap.conf
	cat >/etc/ssh/sshd_config.d/99-bootstrap.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin prohibit-password
PermitEmptyPasswords no
AllowUsers root
UseDNS no
EOF

	install -d -m 0755 /run/sshd
	/usr/sbin/sshd -t

	# Generate a distinct host identity whenever a new runtime starts.
	find /etc/ssh -maxdepth 1 -type f \
		\( -name 'ssh_host_*_key' -o -name 'ssh_host_*_key.pub' \) -delete
}

if [[ $environment == "--configure-ssh" ]]; then
	configure_ssh
	exit 0
fi

mise bootstrap --env "$environment" --yes --force-dotfiles
if [[ $environment == "dev" ]]; then
	configure_ssh
fi
