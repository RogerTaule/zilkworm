
eest_blockchain_tests eest-blockchain-tests: 
	cmake -B build/eest -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DTESTS_DIR=third_party/eest-fixtures/blockchain_tests
	cmake --build build/eest
	ctest --test-dir build/eest --parallel

rv32im_eest_blockchain_tests: 
	cd qemu_runner && make rv32im_eest_blockchain_tests
