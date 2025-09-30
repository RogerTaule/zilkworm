<p align="center">
<img width="360" height="120" alt="z6m logo" src="https://github.com/user-attachments/assets/4f48edc9-9db7-4fe0-a4a6-d3aafdfeb741" />
</p>

Prototype implementation of Silkworm to run on ZKVM provers with native support for RISC-V targets (e.g. rv32im)

To run

```
# Help
$ docker run somnergy/z6m_prover --help
Usage: z6m_prover [OPTIONS]

Options:
      --setup                    Run setup only: produce pk/vk and save to disk
      --execute                  Execute the guest program without proving
      --prove                    Prove using an existing pk (reads pk_path) and save proof to disk
      --verify                   Verify a proof from disk against a vk from disk
      --n <N>                    First input written to SP1Stdin [default: 1]
      --file-name <FILE_NAME>    JSON file to read, minify, and pass as bytes to the guest (second input) [default: test.json]
      --pk-path <PK_PATH>        File path to persist/read proving key [default: pk.bin]
      --vk-path <VK_PATH>        File path to persist/read verifying key [default: vk.bin]
      --proof-path <PROOF_PATH>  File path to persist/read proof [default: proof.bin]
  -h, --help                     Print help
  -V, --version                  Print version

```

### Examples
```
docker run --rm -v "$PWD:/work" -w /work somnergy/z6m_prover --execute --n 1 --file-name test.json
docker run --rm -v "$PWD:/work" -w /work somnergy/z6m_prover --setup --prove --n 1 --file-name test.json
```

### NVIDIA CUDA Accelerated proving
First make sure to install NVIDIA drivers and the NVIDIA Container Toolkit https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
```
$ user@machine-with-gpu
docker run --gpus all --rm --network host -v "$PWD:/work:rw" -v /var/run/docker.sock:/var/run/docker.sock  -w /work -it --entrypoint bash somnergy/z6m_prover

root@instance-20250919-091229:/work# 
SP1_PROVER=cuda RUST_BACKTRACE=full RUST_LOG=info --prove --n 1 --file-name test.json
```
```
docker run --gpus all --rm --network host -v "$PWD:/work:rw" -v /var/run/docker.sock:/var/run/docker.sock  -w /work -it somnergy/z6m_prover

docker run -v "$PWD:/work:rw" -w /work -it somnergy/z6m_prover fetch --block-number 0
docker run --gpus all --rm --network host -v "$PWD:/work:rw" -v /var/run/docker.sock:/var/run/docker.sock  -w /work \
-e SP1_PROVER=cuda -e RUST_BACKTRACE=full -e RUST_LOG=info -it somnergy/z6m_prover prove --block-number 23469366
```

Usage

Direct use docker to get started with dev work
```
docker pull somnergy/z6m:latest
cp -R ~/.workspaces/z6m /workspaces/z6m && cd /workspaces/z6m
su vscode
```
You may need to do `gh auth login` to fetch the latest commits.
Now the code is in `/workspaces/z6m` all ready to go

