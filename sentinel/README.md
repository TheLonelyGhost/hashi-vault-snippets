# Sentinel policies

## Deciding to use Sentinel policies

Unlike Terraform, Vault splits up Sentinel usage between Role-governing policies
(RGP) and Endpoint-governing policies (EGP). There is an explainer of what all
this means relative to Vault's built-in ACL system available in the [HashiCorp
developer documentation](https://developer.hashicorp.com/vault/docs/enterprise/sentinel).
This leaves most of those decisions out of scope for the current discussion.

### Which policy type is most appropriate (EGP, RGP, ACL)

By default, start by assuming you will write an ACL policy. They are far more
performant, available in Vault without an enterprise license, and are only
evaluated when attached to the token or identity (entity or a group to which
the entity is a member).

- When an ACL policy is not powerful enough (RGP or EGP)
- When specifically limiting how to use a particular auth method (EGP)
- When execution time of the Sentinel code is longer than 1ms (ACL)

In general, Sentinel policies run on every single request. The additional
execution time can slow down that request/response lifecycle, a factor about
which applications integrating with Vault might be sensitive. Terraform
Enterprise, where Sentinel is more commonly used, is no big deal if there
are 2 extra seconds to process a set of complex rules. Vault serving secrets
at runtime, 2 extra seconds is, more than likely, an unreasonably long time
to add to the HTTP response time.

### How to apply each policy

EGPs apply to any traffic on a given endpoint (i.e., URI path). All traffice that
applies based on that path will evaluate the policy.

ACL policies are applied on either a Vault Token or a Vault identity (Entity or
Group).

RGPs are assigned like ACL policies (to the token or identity), but restrict what
ACL policies already allow. They are assigned by name in the same way ACL policies
are assigned by name.

## How to read the contents of this folder

Within the `policies/` directory, there are files named according to the
purposes of each sentinel policy. Each file ends in either `.rgp.sentinel`
or `.egp.sentinel`. These suffixes indicate whether it is a Role-governing
policy (RGP) or Endpoint-governing policy.

Within each file, an extended comment block is included. With Terraform Enterprise's

Sentinel is a language for which there are few developer tool integrations
available. As such, we must rely heavily on the `sentinel` binary for syntax
checks and static analysis.
