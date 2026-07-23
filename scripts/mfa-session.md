# mfa-session.sh

Writes short-lived AWS credentials for one function-specific operator role to
`~/.aws/eks-devcontainer/credentials [csoc]`. Run it on the host before
opening or rebuilding the devcontainer.

## Usage

```bash
# Default role: infrastructure-admin; default user alias: primary
bash scripts/mfa-session.sh <MFA_CODE>

# Select another enabled and assigned role
bash scripts/mfa-session.sh <MFA_CODE> --role-key platform-operator

# Explicit overrides remain available
bash scripts/mfa-session.sh <MFA_CODE> \
  --role-key infrastructure-admin \
  --user-key primary \
  --duration 3600

# Trusted setup fallback: copy credentials without role assumption
bash scripts/mfa-session.sh --no-mfa --profile SOURCE_PROFILE
```

The script reads `outputs/aws-csoc-operator-iam.json`. Generate that ignored,
mode-0600 file explicitly after applying reviewed operator IAM:

```bash
bash scripts/operator-profile.sh
```

The file contains only a source profile name, the default role key, role ARNs,
and MFA device ARNs. Terraform does not create local AWS profile artifacts.
Sensitive MFA enrollment data remains a sensitive Terraform output and is not
included.

The normal path calls STS with the selected exact role and MFA device, then
writes expiring credentials and session metadata. The source IAM user must be
assigned to the selected role in `aws-csoc-operator-iam`.

Common failures:

| Error | Resolution |
| --- | --- |
| Missing profile JSON | Run `scripts/operator-profile.sh` or supply explicit environment/CLI values. |
| Unknown role key | Enable and assign the role, apply the reviewed plan, then regenerate the profile JSON. |
| `AWS_SHARED_CREDENTIALS_FILE` is set | Unset the stale variable before invoking the host script. |
| Invalid authentication code | Wait for the next authenticator cycle and retry. |
