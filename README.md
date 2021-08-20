# riscv-core-ruby

A Ruby version of the George Hotz RISC-V core 

---

## Prerequisites

* [riscv-gnu-toolchain](https://github.com/riscv/riscv-gnu-toolchain) - install **riscv64-unknown-elf-gcc** with **newLib**
* [riscv-tests](https://github.com/riscv/riscv-tests) - place it inside the project directory, build locally without prefix 
* `ruby 2.4+` via https://rvm.io/

---

Install ruby dependencies:

```
bundle install
```

Run all `p tests` with the core:

```
ruby cpu.rb
```
