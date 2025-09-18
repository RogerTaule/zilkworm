## This is to be built locally on an environment already working with the build

FROM ubuntu:25.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Non-root user for safety
RUN useradd -m -u 10001 appuser
WORKDIR /appuser

COPY --chown=appuser:appuser ./target/release/z6m_prover /usr/local/bin/z6m_prover
COPY --chown=appuser:appuser ./target/elf-compilation/riscv32im-succinct-zkvm-elf/release/z6m_guest /usr/local/bin/z6m_guest



USER appuser
ENTRYPOINT ["/usr/local/bin/z6m_prover"]
CMD ["--help"]