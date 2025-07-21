function build
    set version (grep '.version = ' build.zig.zon | awk -F'"' '{print $2}')
    towncrier build --yes --version $version
    zig build --release=fast
    mkdir -p out
    tar -czf out/cluster_ping_Linux_amd64.tar.gz --transform 's|.*/||' zig-out/bin/cluster_ping README.md CHANGELOG.md examples/current_cluster.fish
end

build