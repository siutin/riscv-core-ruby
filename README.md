# riscv-core-ruby

A Ruby version of the George Hotz RISC-V core 

---

## Prerequisites

* [riscv-gnu-toolchain](https://github.com/riscv/riscv-gnu-toolchain) - install **riscv64-unknown-elf-gcc** with **newLib**

```
#= 1 - Install sysem dependencies

# Ubuntu
sudo apt-get install autoconf automake autotools-dev curl python3 libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils 
bc zlib1g-dev libexpat-dev

# Fedora/CentOS/RHEL OS
sudo yum install autoconf automake python3 libmpc-devel mpfr-devel gmp-devel gawk  bison flex texinfo patchutils gcc gcc-c++ zlib-devel expat-devel
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain

# Arch Linux
pacman -Syyu autoconf automake curl python3 mpc mpfr gmp gawk base-devel bison flex texinfo gperf libtool patchutils bc zlib expat

# OS X with homebrew
brew install python3 gawk gnu-sed gmp mpfr libmpc isl zlib expat
brew tap discoteq/discoteq
brew install flock

#= 2 - Build Newlib cross-compiler
./configure --prefix=/opt/riscv
make

#= 3 - Set PATH environment to include `/opt/riscv/bin`
export PATH="$PATH:/opt/riscv/bin"
```
* `ruby 2.4+` via https://rvm.io/

```
gpg2 --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
\curl -sSL https://get.rvm.io | bash -s stable --ruby
```

---

## Installation

1. Clone this project

```
git clone git@github.com:siutin/riscv-core-ruby.git
cd riscv-core-ruby
```

2. Clone and build `riscv-tests`

```
git clone https://github.com/riscv/riscv-tests
cd riscv-tests
git submodule update --init --recursive
autoconf
./configure
make
make install
cd ..
```

3. Install ruby dependencies:

```
bundle install
```

---

## Run RSICV test with the core

```
ruby cpu.rb
```
