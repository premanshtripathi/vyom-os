# VyomOS 🌌

An independent operating system engineered entirely from scratch. VyomOS is designed to establish a robust foundation in low-level kernel architecture, memory management, and direct hardware control, with a vision for future hardware abstraction and scalability.

## 🏗️ Architecture & Current State
**Current Target:** `x86 Architecture`
- The system currently boots and operates in **16-bit Real Mode**.
- Active development is focused on the transition into **32-bit Protected Mode**, establishing a scalable C kernel.
- Includes a validated C-reference utility (`fat.c`) for FAT12 filesystem parsing and LBA calculation before native Assembly implementation.

## 🚀 Core Features
- **Custom Bootloader:** Interacts directly with BIOS interrupts (`INT 13h`, `INT 10h`) to initialize the system, configure the stack, and read from raw storage.
- **FAT12 File System Support:** Native FAT12 BPB (BIOS Parameter Block) setup and 12-bit cluster chain traversal logic.
- **Standalone File System Utility:** A custom C-based CLI tool to parse, debug, and extract files natively from FAT12 floppy images.
- **Automated Build System:** A robust `Makefile` toolchain utilizing `nasm`, `dd`, `mkfs.fat`, and `mcopy` to assemble binaries and generate bootable `.img` files seamlessly.

## 📁 Repository Structure
```text
vyom-os/
├── src/
│   ├── bootloader/     # 16-bit real mode bootloader (boot.asm)
│   └── kernel/         # Kernel entry point (main.asm)
├── tools/
│   └── fat/            # C-based FAT12 parser and CLI tool (fat.c)
├── .gitignore          # Git ignore rules
├── bochs_config        # Bochs emulator configuration file
├── debug.sh            # Bochs hardware debugging script
├── LICENSE             # MIT License
├── Makefile            # Build automation toolchain
├── README.md           # Project documentation
├── run.sh              # QEMU execution script
└── test.txt            # Text file for FAT12 reading validation
```

*(Note: Compiled binaries and disk images are generated in a local `build/` directory which is git-ignored).*

## 🛠️ Prerequisites

To build and run VyomOS, your development environment needs the following dependencies:

* **`nasm`**: For assembling x86 Assembly code.
* **`gcc`**: For compiling the C-based tools.
* **`qemu-system-i386`**: For quick hardware emulation.
* **`bochs`**: For deep, cycle-accurate hardware debugging.
* **`dosfstools` & `mtools**`: For `mkfs.fat` and `mcopy` to generate and manipulate FAT12 floppy images.

## ⚙️ Build and Run Instructions

### 1. Build the OS and Disk Image

To compile the bootloader, kernel, and the FAT utility, and to generate the bootable floppy image (`main_floppy.img`), run:

```bash
make all

```

### 2. Run in Emulator

You can quickly boot VyomOS using QEMU by running the provided shell script:

```bash
./run.sh

```

### 3. Debug with Bochs

To run the system in Bochs with the enhanced GUI debugger for inspecting memory, registers, and interrupts:

```bash
./debug.sh

```

### 4. Test the FAT12 Utility

You can use the built C utility to read files directly from the generated FAT12 disk image. *(Note: The file name must be exactly 11 characters, padded with spaces as per FAT12 specifications).*

```bash
./build/tools/fat build/main_floppy.img "TEST    TXT"

```

## 🎯 Project Vision & Roadmap

The upcoming roadmap for VyomOS includes:

* Translating FAT12 read logic entirely into x86 Assembly.
* Full transition from Real Mode to **32-bit Protected Mode** (GDT setup).
* Implementing Memory Paging and Interrupt Service Routines (ISRs).
* Virtual File System (VFS) and eventual multi-tasking capabilities.

## 📄 License

This project is licensed under the [MIT License](https://www.google.com/search?q=LICENSE).

---

## 🙏 Acknowledgments
The foundational architecture and early development of this project are heavily inspired by and built following the excellent [Building an OS](https://youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN) playlist by [nanobyte](https://www.youtube.com/@nanobyte-dev). Huge thanks to the creator for providing such an incredible and accessible resource for bare-metal programming.

---
*Developed and maintained by [Premansh Tripathi](https://github.com/premanshtripathi).*