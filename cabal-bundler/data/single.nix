{ stdenv
, ghc
, cabal-install
, gcc
, zlib
}:

let
  hackageTarball = name: version: sha256: rest:
    let
      # We need a source tarball, note we use fetchurl: we know the hash of tarball, not "nar".
      tarball = builtins.fetchurl {
        url    = "http://hackage.haskell.org/package/${name}-${version}/${name}-${version}.tar.gz";
        sha256 = sha256;
      };

      unpackedTarball = stdenv.mkDerivation {
        name    = "${name}-${version}-unpacked";
        tarball = tarball;
        # we only install
        phases = ["installPhase"];
        installPhase = ''
          echo $out
          echo $tarball
          mkdir -p $out
          tar -xvz --directory $out --strip-components=1 -f $tarball
        '';
      };

      # If revision is specified, we fetch the revision;
      # and make new source derivation
      # with .cabal file changed
      patchedTarball = if  rest ? rev == false then unpackedTarball else
        let
          rev = toString rest.rev;

          cabalFile = builtins.fetchurl {
            url    = "http://hackage.haskell.org/package/${name}-${version}/revision/${rev}.cabal";
            sha256 = rest.sha256;
          };

          # The result is simple:
          # - copy original sources
          # - overwrite with revisioned .cabal file
          patched = stdenv.mkDerivation {
            name = "${name}-${version}-r${rev}-source";
            pkgName   = name;
            sources   = unpackedTarball;
            cabalFile = cabalFile;

            # we only install
            phases = ["installPhase"];

            installPhase = ''
              echo out $out
              echo sources $sources
              echo cabalfile $cabalFile
              mkdir -p $out
              cp -r $sources/* $out
              rm -f $out/${name}.cabal
              cp $cabalFile $out/${name}.cabal
            '';
          };

        in patched;

    in patchedTarball;
in

stdenv.mkDerivation {
  name = "{{derivationName}}";

  buildCommand = ''
    TOPDIR=$(pwd)

    CC=$gcc/bin/gcc
    HC=$ghc/bin/ghc
    HCPKG=$ghc/bin/ghc-pkg
    CABAL=$cabal/bin/cabal

    echo "Tools: $CC $HC $HCPKG $CABAL"

    export LANG=C.utf8
    export CABAL_DIR=$TOPDIR/.cabal
    export CABAL_CONFIG=$CABAL_DIR/config

    mkdir -p $CABAL_DIR
    cat > $CABAL_CONFIG <<EOF
    -- doesn't work
    -- https://github.com/haskell/cabal/issues/5956
    verbose: normal +nowrap
    jobs: $NIX_BUILD_CORES

    -- No global repository, all deps should exist in global package-db
    -- repository hackage.haskell.org
    --   url: http://hackage.haskell.org/

    remote-repo-cache:      $CABAL_DIR/packages

    -- cabal-install-2.2 doesn't know this yet :/
    -- write-ghc-environment-files: never

    build-summary:     $CABAL_DIR/logs/build.log
    extra-prog-path:   $CABAL_DIR/bin
    -- installdir:        $CABAL_DIR/bin
    logs-dir:          $CABAL_DIR/logs
    store-dir:         $CABAL_DIR/store
    symlink-bindir:    $CABAL_DIR/bin
    world-file:        $CABAL_DIR/world

    install-dirs user
    EOF

    # Tool versions
    ###############

    $HC --version
    $CABAL --version

    echo "Generating project file"
    ##############################

    cat > cabal.project <<EOF
    tests: False
    benchmarks: False
    documentation: False
    EOF

    for dep in $hsdeps; do
      echo "packages: $dep/*.cabal" >> cabal.project
    done

    for dep in $cdeps; do
      if [ -d "$dep/lib" ]; then
        echo "extra-lib-dirs: $dep/lib" >> cabal.project
      fi
      if [ -d "$dep/include" ]; then
        echo "extra-include-dirs: $dep/include" >> cabal.project
      fi
    done

    echo "Building project"
    #######################

    $CABAL new-build -vverbose+nowrap --with-compiler=$HC --with-ghc=$CC "$targetComp"

    echo "Install built artifact"
    ##########################################

    mkdir -p $out/bin
    cp $(find dist-newstyle -name "$targetExe" -type f -executable | head -n1) $out/bin
  '';

  # Compiler
  ghc     = ghc;
  cabal   = cabal-install;
  gcc     = gcc;

  # Target
  targetComp = "{{componentName}}";
  targetExe  = "{{executableName}}";

  # Dependencies
  cdeps   = [
{% for dep in cdeps %}
    {{ dep }}
{% endfor %}
    ];
  hsdeps  = builtins.attrValues {
{% for dep in hsdeps %}
    {{dep.name}} = hackageTarball "{{dep.name}}" "{{dep.version}}" "{{dep.sha256}}" {{dep.revision }};
{% endfor %}
  };
}
