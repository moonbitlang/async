build:
    moon build -C examples
    cmake -B examples/build -S examples
    make -C examples/build -j 8

clean:
    rm -rf examples/build
    moon clean -C examples