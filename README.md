# 🐉 DragonDriver

> **Experimental learning project – not intended for production use**

DragonDriver is a **personal experimental project** created for learning and exploration purposes only.  
The main goal is to better understand:

- Vulkan driver behavior on Adreno GPUs
- Mesa / Turnip internals
- CI automation workflows
- D3D12 translation layers (such as VKD3D-Proton)
- Tooling, patching, and build experimentation

This repository **does not aim to provide a secure, stable, or production-ready driver**.

---

## ⚠️ Important Notice

This project is:
- **Experimental**
- **Unstable by design**
- **Not security-audited**
- **Not recommended for daily or production use**

If you are looking for **reliable and well-maintained solutions**, please refer to the projects listed below.

---

## 🎯 Purpose of This Repository

DragonDriver exists mainly to:

- Learn how CI pipelines work for driver-related projects
- Experiment with feature exposure and capability reporting
- Test interactions between Vulkan drivers and D3D12 translation layers
- Understand limitations, edge cases, and real-world behavior on Android / Adreno devices

Mistakes, rough patches, and incomplete ideas are **expected and intentional** as part of the learning process.

---

## 🧪 Scope

This repository may include:
- Experimental scripts
- CI workflows
- Feature toggles and patches
- Local testing utilities

It **does not** represent official Mesa, Turnip, or VKD3D-Proton development.

---

## 🔗 Recommended Projects (Production-Grade)

If your goal is performance, stability, or real-world usage, please check these excellent projects by experienced developers:

- **AdrenoToolsDrivers**  
  https://github.com/K11MCH1/AdrenoToolsDrivers

- **freedreno_turnip-CI**  
  https://github.com/StevenMXZ/freedreno_turnip-CI

These repositories are actively maintained and built with production use in mind.

---

## 🙏 Credits & Inspiration

This project is inspired by the work of Mesa, Freedreno, Turnip, VKD3D-Proton developers, and the wider open-source graphics community.

All credit goes to the upstream developers pushing the ecosystem forward.

---

## 📌 Final Notes

DragonDriver is simply a **starting point** — a sandbox for learning and experimentation.  
Nothing more, nothing less.
