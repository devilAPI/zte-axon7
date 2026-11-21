# IPA v2.5 (mobile data) on the ZTE Axon 7

Work started 2026-11-21. This file collects the researched prior art and the
evidence for the kernel port. It is not a user-visible "works" claim until the
test section at the bottom is filled in with measurements from the phone.

## The problem

MSM8996 has IPA v2.5: a 32-bit IPA microcontroller and BAM DMA. Mainline
`drivers/net/ipa` (enabled as `CONFIG_QCOM_IPA=m` in our config) starts at
IPA v3.0/v3.1 and assumes GSI, so the DT has no IPA node on msm8996, no
`rmnet_ipa0` appears and mobile data cannot work.

## Prior art studied

1. Sireesh Kodali, "[RFC PATCH 00/17] net: ipa: Add support for IPA v2.x",
   2021-09-20: <https://lore.kernel.org/all/20210920030811.57273-1-sireeshkodali1@gmail.com/>.
   The series is also in Patchwork (linux-arm-msm series 549525). It adds
   `qcom,ipa-v2.5`, a 32-bit `struct ipa` layout, BAM as a DMA transport via a
   new `ipa_dma` abstraction, and `ipa_data-v2.c` for MSM8996/MSM8953/SDM660.
   The cover letter reports an IP address on MSM8996 with ModemManager. It is
   based on Linux 5.13, depends on two separate BAM patches (DMA metadata and
   immediate commands), and refactors most of `drivers/net/ipa` as it existed
   in 5.13. Patch 03/17 ("Refactor GSI code") is missing from Patchwork; it is
   archived as a mailing-list commit in
   `linux-mailinglist-archives/linux-kernel.vger.kernel.org.2`.
2. A later, rebased implementation exists as `ipa2-lite`: a self-contained
   IPA v2.x driver for mainline kernels from the msm8953-mainline tree, carried
   with MSM8996 fixes by the Xiaomi Mi MIX (lithium) port:
   <https://github.com/milohr/xiaomi_mi_mix_linux/tree/main/kernel/patches>
   (0026 = driver, 0033 = IPA v2.5/BAM-remote-mode, 0039 = QMAPv4 checksum
   offload, 0043 = TX/lifetime fixes). The Mi MIX uses the same MSM8996 SoC and
   IPA v2.5. Its notes
   (<https://github.com/milohr/xiaomi_mi_mix_linux/blob/main/docs/PHASE6_FINDINGS.md>)
   report: resetting the IPA BAM from Linux resets the SoC because the modem/TZ
   owns it (`qcom,ipa-bam-remote-mode` downstream); after skipping the BAM
   globals and zeroing the v2.5 header processing context, the driver probes
   and creates `rmnet_ipa0`. The module must only be loaded while the modem is
   running. Data (UMTS, Movistar CO) worked there after the QMAPv4 fixes; that
   test used a SIM, which we do not have.

We use the second implementation: it needs no refactor of `drivers/net/ipa`
(which has changed heavily since 5.13), and it carries the MSM8996 BAM
ownership fix that the RFC lacks. The RFC remains the register/endpoint
reference.

## Kernel changes

* Nura patches 0060-0063 (`postmarketos/pmaports-local/device/testing/linux-zte-axon7/`):
  ipa2-lite driver, MSM8996 v2.5/BAM fixes, QMAPv4 + lifetime fixes, and the
  DT nodes (IPA at 0x680000 with `qcom,bam-remote-mode`, IPA entries in the
  MSS SMP2P).
* `config-zte-axon7.aarch64`: `CONFIG_QCOM_IPA2_LITE=m` (the existing
  `CONFIG_QCOM_IPA=m` stays for newer SoCs). The module is deliberately not
  loaded from `modules-load.d`: it must be loaded only after the modem runs.

## Build evidence

(to be filled in)

## Phone evidence

(to be filled in)
