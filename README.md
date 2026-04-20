# 🚀 Microprocessor System & Implementation Projects

This repository contains a collection of projects from the course **Microprocessor System and Implementation**, focusing on **computer architecture, hardware-software co-design, and system-level performance analysis**.

---

## 📌 Overview

These projects explore key components of modern processor systems, including:

* Hardware/Software co-profiling
* Branch prediction mechanisms
* Cache design and optimization
* Real-Time Operating Systems (FreeRTOS)
* Domain-Specific Accelerators (DSA)

The goal is to **analyze performance bottlenecks and design hardware-aware optimizations**.

All experiments and measurements were conducted on a real FPGA platform (Arty A7-100T) and executed on the Aquila RISC-V CPU developed by NYCU EISL Lab, ensuring that the results reflect practical hardware behavior rather than simulation-only assumptions.

🔗 Aquila CPU: https://github.com/eisl-nctu/aquila
---

## 📂 Project List

### 🔹 1. Hardware/Software Co-Profiling System

📄 [Report](./hw-sw-profiling/Real-time_Analysis_of_a_HW-SW_Platform.pdf)

* Compared **software profiling (gprof)** with hardware cycle-level profiling
* Implemented profiling logic in Verilog
* Identified discrepancies between estimated and actual runtime behavior

**Key Insight:**
Software profiling alone cannot accurately capture real hardware execution characteristics, highlighting the necessity of hardware-aware performance analysis.

---

### 🔹 2. Branch Prediction Mechanisms

📄 [Report](./bpu/Analysis_of_BPU.pdf)

* Evaluated impact of BHT size on prediction accuracy
* Implemented and analyzed **TAGE predictor architecture**
* Reduced misprediction penalty in pipeline

**Key Insight:**
Branch misprediction is a major source of pipeline stalls; improving prediction accuracy directly enhances CPU performance.

---

### 🔹 3. Cache Design and Optimization

📄 [Report](./dcache/Dcache_Analysis_and_Pseudo-LRU_Optimization.pdf)

* Analyzed cache hit/miss rate and latency behavior
* Designed a **Pseudo-LRU replacement policy**
* Improved cache efficiency and hit rate

**Key Insight:**
Memory hierarchy behavior dominates runtime performance, especially under irregular access patterns.

---

### 🔹 4. Real-Time Operating Systems (FreeRTOS)

📄 [Report](./freertos/FreeRTOS_Analysis.pdf)

* Analyzed context switching mechanism and trap handling
* Measured overhead of interrupts, yielding, and synchronization
* Studied scheduling impact under different time quantum

**Key Insight:**
Scheduling and synchronization introduce non-trivial overhead that affects real-time system performance.

---

### 🔹 5. Domain-Specific Accelerators (DSA)

📄 [Report](./dsa/Domain_Specific_Accelerator.pdf)

* Designed a hardware accelerator for floating-point inner product
* Integrated via **MMIO interface**
* Achieved significant speedup over CPU execution

**Key Insight:**
Hardware specialization provides substantial performance gains for structured workloads such as CNN computation.

---

## 🛠 Technical Stack

* **Processor:** Aquila RISC-V CPU
* **Hardware Design:** Verilog
* **Software:** C / FreeRTOS
* **Platform:** FPGA (ARTY 100T)

---

