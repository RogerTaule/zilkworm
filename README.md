<p align="center">
<img width="360" height="120" alt="z6m logo" src="https://github.com/user-attachments/assets/4f48edc9-9db7-4fe0-a4a6-d3aafdfeb741" />
</p>

Prototype implementation of Silkworm to run on ZKVM provers with native support for RISC-V targets (e.g. rv32im)

To run

```
# Help
$ docker run somnergy/z6m_prover help
Usage: z6m_prover [OPTIONS] [COMMAND]

Commands:
  setup    Run setup to generate proving and verifying keys
  fetch    Fetch block and witness from RPC
  execute  Execute the guest program without proving
  prove    Generate a proof for a block
  verify   Verify a proof using a verification key
  help     Print this message or the help of the given subcommand(s)

Options:
      --service                                      
      --rpc-url <RPC_URL>                            
      --websocket-url <WEBSOCKET_URL>                
      --data-dir <DATA_DIR>                          [default: temp]
      --save-all-responses                           
      --prove-every <PROVE_EVERY>                    
      --execute-every <EXECUTE_EVERY>                
      --post-every <POST_EVERY>                      
      --start-block <START_BLOCK>                    
      --pk-path <PK_PATH>                            
      --proof-type <PROOF_TYPE>                      [default: compressed]
      --ethproofs-endpoint <ETHPROOFS_ENDPOINT>      
      --ethproofs-token <ETHPROOFS_TOKEN>            
      --ethproofs-cluster-id <ETHPROOFS_CLUSTER_ID>  
      --ethproofs-hook-id <ETHPROOFS_HOOK_ID>        
  -h, --help                                         Print help
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

docker run -v "$PWD:/work:rw" -w /work -it somnergy/z6m_prover fetch --block-number 0 --rpc-url https://reth-ethereum.ithaca.xyz/rpc 
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

