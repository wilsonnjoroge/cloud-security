# Cloud Security Portfolio

**A multi-cloud security engineering portfolio: hands-on architecture, hardening, detection, and incident response, organized by cloud platform.**

![Status](https://img.shields.io/badge/status-active-orange)
![Focus](https://img.shields.io/badge/focus-Cloud%20Security%20%7C%20DFIR-blue)
![Target](https://img.shields.io/badge/target-AWS%20Certified%20Security%20--%20Specialty-232F3E)

---

## About This Repository

This is the umbrella repository for my cloud security work: each major cloud platform lives in its own dedicated subfolder, built and documented independently, but following the same underlying discipline throughout: architecture decisions made for security first, every control tested (not just configured), and forensic readiness treated as a design choice rather than an afterthought.

Work here is applied and hands-on: real environments built, hardened, attacked, and investigated, documented step by step with evidence.

---

## Structure

```
cloud-security/
├── aws-security/        AWS security architecture, DFIR & offensive validation capstone
├── azure-security/       (planned)
├── gcp-security/          (planned)
├── terraform-iac/        (planned): cross-cloud Infrastructure as Code
├── README.md
└── LICENSE.md
```

---

## aws-security: Active

A 29-document, four-phase build of an enterprise-grade AWS environment, following the AWS Well-Architected Framework: network, identity, compute, detection, forensics, and offensive validation, modeled on a fictional PCI-DSS fintech (AcmeFintech Ltd).

**Currently published:** Phase 1: Foundations (VPC, IAM, EC2, S3, Security Groups & NACLs, CloudTrail, CloudWatch, Billing & Cost Controls). Later phases (Detection & Hardening, Forensics & Incident Response, Offensive Validation, and the full capstone build) are in progress and published incrementally as each is completed and verified.

Documented publicly alongside a 30-day technical series building toward **AWS Certified Security – Specialty**.

→ [`aws-security/README.md`](./aws-security/README.md) for the full roadmap, doc index, and completion tracker.

---

## azure-security: Planned

Security architecture and hardening on Microsoft Azure, following the same build-harden-detect-investigate structure as the AWS work. Will cover identity (Entra ID / RBAC), network segmentation (VNets, NSGs), monitoring (Microsoft Defender for Cloud, Sentinel), and incident response patterns specific to Azure.

---

## gcp-security: Planned

Security architecture on Google Cloud Platform, covering IAM, VPC design, Security Command Center, and detection/response patterns specific to GCP.

---

## terraform-iac: Planned

Cross-cloud Infrastructure as Code, provisioning the same architectural patterns built manually in `aws-security` (and later `azure-security`, `gcp-security`) through Terraform instead of console clicks: version-controlled, peer-reviewable infrastructure, matching how these environments are actually provisioned at enterprise scale.

---

## Related Independent Work

- [**soc-detection-lab**](https://github.com/wilsonnjoroge/soc-detection-lab): Wazuh SIEM and Suricata network IDS deployment, host and network-based detection correlation
- [**vulnerability-assessment**](https://github.com/wilsonnjoroge/vulnerability-assessment): Structured VAPT of Metasploitable2, 47 vulnerabilities identified across 23 services, full remediation roadmap

---

## Author

**Wilson Njoroge Wanderi**, CCEP, CC, KCNA, ITIL®4
Cloud Security Specialist (AWS) | Enterprise Middleware Engineer
MSc Cybersecurity & Digital Forensics: Open University of Kenya

[LinkedIn](https://www.linkedin.com/in/wilson-njoroge-wanderi-ccep-cc-kcna-itil%C2%AE4-33b615166/) · [GitHub](https://github.com/wilsonnjoroge)

---

## Disclaimer

All infrastructure, company names, and data used across this portfolio are fictional and built exclusively within isolated, cost-controlled cloud lab environments for educational and portfolio purposes. No production or customer data is used at any stage.

---

## License

Licensed under Apache 2.0: see [LICENSE.md](LICENSE.md). Reuse with attribution.
