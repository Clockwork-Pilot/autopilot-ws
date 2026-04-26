# Project-specific stack on top of the minimal autopilot-ws-base.
# Built via:
#   ./build-docker-workspace.sh user.Dockerfile

FROM autopilot-ws-base

USER root

# Editors, networking, debugging, general dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      aggregate \
      build-essential \
      gdb \
      gnupg2 \
      libicu-dev \
      lsb-release \
      man-db \
      pinentry-curses \
      nano \
      vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
      clang \
      cmake \
      libclang-dev \
      libssl-dev \
      llvm-dev \
      pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Tcl headers — sqlite testfixture build expects them in non-versioned paths
RUN apt-get update && apt-get install -y --no-install-recommends \
      tcl tcl-dev tcllib \
      tcl8.6 tcl8.6-dev tcl8.6-tdbc tcl8.6-tdbc-sqlite3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/include/tcl/tcl.h /usr/include/tcl.h \
    && ln -s /usr/include/tcl/tclOODecls.h /usr/include/tclOODecls.h \
    && ln -s /usr/include/tcl/tclPlatDecls.h /usr/include/tclPlatDecls.h \
    && ln -s /usr/include/tcl/tclDecls.h /usr/include/tclDecls.h \
    && ln -s /usr/include/tcl/tclTomMath.h /usr/include/tclTomMath.h \
    && ln -s /usr/include/tcl/tclTomMathDecls.h /usr/include/tclTomMathDecls.h \
    && ln -s /usr/lib/tclConfig.sh /usr/lib64/tclConfig.sh

# Valgrind for native debugging
RUN apt-get update && apt-get install -y --no-install-recommends \
      valgrind \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# uv — fast Python package manager (installed as root)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Sqlite workspace at /sqlite, owned by node so it can configure/make
RUN mkdir -p /sqlite && chown -R node:node /sqlite

USER node

RUN cd /sqlite && \
    wget https://sqlite.org/2026/sqlite-src-3510200.zip && \
    ls /sqlite && \
    unzip /sqlite/sqlite-src-3510200.zip -d /sqlite && \
    rm /sqlite/sqlite-src-3510200.zip && \
    mv /sqlite/sqlite-src-3510200/* /sqlite/ && \
    rm -rf /sqlite/sqlite-src-3510200 && \
    cd /sqlite && \
    ./configure --all --disable-amalgamation && make && rm *.o

RUN rustup install nightly-2026-03-26-x86_64-unknown-linux-gnu \
    && rustup component add --toolchain nightly-2026-03-26-x86_64-unknown-linux-gnu \
       rustfmt rust-analyzer clippy

RUN rustup toolchain install nightly --profile minimal \
    && rustup component add --toolchain nightly rustfmt rust-analyzer clippy \
    && rustup toolchain install stable \
    && rustup component add --toolchain stable rustfmt rust-analyzer clippy \
    && rustup default stable

USER root
