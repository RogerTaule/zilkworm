//! A simple program that takes sample runs silkworm's state transition

// These two lines are necessary for the program to properly compile.
//
// Under the hood, we wrap your main function with some extra code so that it behaves properly
// inside the zkVM.
#![no_main]

// use crate::ffi::sample_run_wrapped;
sp1_zkvm::entrypoint!(main);

// src/main.rs
#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("wrapper.hpp");
        fn sample_run_wrapped() -> u64;
    }
}

pub fn main() {
    let _result: u64 = ffi::sample_run_wrapped();
    sp1_zkvm::io::commit(&_result);
}
