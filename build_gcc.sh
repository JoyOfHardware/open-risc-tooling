#!/bin/bash

# Set up error handling
set -ex
set -o pipefail

# Variables
PREFIX=/opt/cross
TARGET=or1k-linux
BINUTILS_VERSION=2.36.1
GCC_VERSION=10.3.0
LINUX_KERNEL_VERSION=6.6.30
GLIBC_VERSION=2.35
MPFR_VERSION=4.1.0
GMP_VERSION=6.2.1
MPC_VERSION=1.2.1
ISL_VERSION=0.22
NCORES=$(nproc)
WORKDIR=$(mktemp -d)

# Install necessary packages
install_packages() {
  sudo apt-get update
  sudo apt-get install -y g++ make gawk wget tar xz-utils bzip2 gcc-multilib
}

# Download source packages
download_sources() {
  pushd $WORKDIR
  wget http://ftpmirror.gnu.org/binutils/binutils-$BINUTILS_VERSION.tar.gz
  wget http://ftpmirror.gnu.org/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.gz
  wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX_KERNEL_VERSION.tar.xz
  wget http://ftpmirror.gnu.org/glibc/glibc-$GLIBC_VERSION.tar.xz
  wget http://ftpmirror.gnu.org/mpfr/mpfr-$MPFR_VERSION.tar.xz
  wget http://ftpmirror.gnu.org/gmp/gmp-$GMP_VERSION.tar.xz
  wget http://ftpmirror.gnu.org/mpc/mpc-$MPC_VERSION.tar.gz
  wget -nc https://sourceforge.net/projects/libisl/files/isl-$ISL_VERSION.tar.xz/download -O isl-$ISL_VERSION.tar.xz
  popd
}

# Extract source packages
extract_sources() {
  pushd $WORKDIR
  for f in *.tar*; do tar xf $f; done
  popd
}

# Create symbolic links for GCC dependencies
create_symlinks() {
  pushd $WORKDIR/gcc-$GCC_VERSION
  ln -s ../mpfr-$MPFR_VERSION mpfr
  ln -s ../gmp-$GMP_VERSION gmp
  ln -s ../mpc-$MPC_VERSION mpc
  ln -s ../isl-$ISL_VERSION isl
  popd
}

# Set up installation directory
setup_installation_directory() {
  sudo mkdir -p $PREFIX
  sudo chown $(whoami) $PREFIX
  export PATH=$PREFIX/bin:$PATH
}

# Build Binutils
build_binutils() {
  mkdir -p $WORKDIR/build-binutils
  pushd $WORKDIR/build-binutils
  ../binutils-$BINUTILS_VERSION/configure \
    --prefix=$PREFIX \
    --target=$TARGET \
    --disable-multilib
  make -j$NCORES
  make install
  popd
}

# Install Linux Kernel Headers
install_kernel_headers() {
  pushd $WORKDIR/linux-$LINUX_KERNEL_VERSION
  make ARCH=arm64 INSTALL_HDR_PATH=$PREFIX/$TARGET headers_install
  popd
}

# Build C/C++ Compilers
build_gcc() {
  mkdir -p $WORKDIR/build-gcc
  pushd $WORKDIR/build-gcc
  ../gcc-$GCC_VERSION/configure \
    --prefix=$PREFIX \
    --target=$TARGET \
    --enable-languages=c,c++ \
    --disable-multilib
  make -j$NCORES all-gcc
  make install-gcc
  popd
}

# Install Standard C Library Headers and Startup Files
install_glibc_headers() {
  mkdir -p $WORKDIR/build-glibc
  pushd $WORKDIR/build-glibc
  ../glibc-$GLIBC_VERSION/configure \
    --prefix=$PREFIX/$TARGET \
    --build=$(../config.guess) \
    --host=$TARGET \
    --target=$TARGET \
    --with-headers=$PREFIX/$TARGET/include \
    --disable-multilib \
    libc_cv_forced_unwind=yes
  make -j$NCORES
  make install
  #make install-bootstrap-headers=yes install-headers
  #make -j$NCORES csu/subdir_lib
  #install csu/crt1.o csu/crti.o csu/crtn.o $PREFIX/$TARGET/lib
  #$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $PREFIX/$TARGET/lib/libc.so
  #touch $PREFIX/$TARGET/include/gnu/stubs.h
  popd
}

# Build Compiler Support Library
build_libgcc() {
  pushd $WORKDIR/build-gcc
  make -j$NCORES all-target-libgcc
  make install-target-libgcc
  popd
}

# Build Standard C Library
build_glibc() {
  pushd $WORKDIR/build-glibc
  make -j$NCORES
  make install
  popd
}

# Build Standard C++ Library
build_libstdcxx() {
  pushd $WORKDIR/build-gcc
  make -j$NCORES
  make install
  popd
}

# Cleanup
cleanup() {
  rm -rf $WORKDIR
}

# Main script
main() {
  install_packages
  download_sources
  extract_sources
  create_symlinks
  setup_installation_directory
  build_binutils
  install_kernel_headers
  build_gcc
  install_glibc_headers
  build_libgcc
  build_glibc
  build_libstdcxx
  cleanup

  echo "GCC cross-compiler for AArch64 has been built and installed to $PREFIX"
}

# Run the main script
main
