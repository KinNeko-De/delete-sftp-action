# SFTP Delete Action for IONOS

This GitHub Action provides reliable SFTP deletion from IONOS hosting.
It was created to clean up feature branch deployments after the branch is deleted, specifically for IONOS accounts created before 10.09.2024.

# Why this action?

IONOS SFTP has several restrictions:

- No SSH access: Only SFTP is available; SSH features and commands do not work.
- Limited SFTP features: Many extended SFTP commands and batch operations are unsupported.
- Recursive deletion: Standard tools (like rsync, scp, or advanced SFTP batch scripts) fail.

This action implements an SFTP deletion strategy that:

- Avoids unsupported SFTP features and batch commands.
- Scans remote directories and files.
- Recursively deletes all content in a specified remote subdirectory.

# Usage

This repository can be used directly as a GitHub Action. Add a step to your workflow that uses this repository. Note: this action expects sshpass and sftp to be available on the runner. GitHub-hosted Ubuntu runners typically include these tools.

# Inputs

| Name           | Required | Default | Description                                         |
|----------------|----------|---------|-----------------------------------------------------|
| ftp_username   | Yes      |         | SFTP username                                       |
| ftp_password   | Yes      |         | SFTP password (use GitHub Secrets)                  |
| ftp_server     | Yes      |         | SFTP server hostname or IP                          |
| ftp_port       | No       | 22      | SFTP port                                           |
| dir_to_delete  | Yes      |         | Remote directory to delete files from on the server |


# Example

```yaml
- name: Delete feature branch deployment via SFTP
  uses: KinNeko-De/delete-sftp-action@v0
  with:
    ftp_username: ${{ secrets.SFTP_USERNAME }}
    ftp_password: ${{ secrets.SFTP_PASSWORD }}
    ftp_server: ${{ secrets.SFTP_SERVER }}
    ftp_port: 22
    dir_to_delete: feature-branch-name
```