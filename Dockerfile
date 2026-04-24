FROM debian:bookworm

ARG TZ
ENV TZ="$TZ"
ENV DEVCONTAINER=true

# Harness contract dependencies:
#   bash, git, gh — entrypoint + proxy_wrapper symlinks
#   curl, wget, ca-certificates — fetching act, general scripting
#   sudo, gosu — entrypoint user drop
#   python3 + pip + venv — claude plugin venv + proxy_wrapper.py
#   jq, less, procps, unzip — common scripting needs
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gh \
      gosu \
      jq \
      less \
      procps \
      python3 \
      python3-pip \
      python3-venv \
      sudo \
      unzip \
      wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG USERNAME=node
ARG HOME=/home/$USERNAME

# Hardcoded UID 1000 is a default identity; the entrypoint rebrands
# `node` to whatever HOST_UID/HOST_GID the caller passes, so published
# images work on any host without build-time UID plumbing.
RUN useradd -m -u 1000 $USERNAME \
    && mkdir -p $HOME/ \
    && chown -R $USERNAME:$USERNAME $HOME/ \
    && usermod -aG tty $USERNAME

# Harness scripts: entrypoint + proxy wrapper for git/gh/chmod
COPY docker-scripts /docker-scripts
RUN cp /docker-scripts/docker-entrypoint.sh /usr/local/bin/ \
    && chmod +x /usr/local/bin/docker-entrypoint.sh \
    && cp /docker-scripts/proxy_wrapper.py /usr/local/bin/proxy_wrapper.py \
    && chmod +x /usr/local/bin/proxy_wrapper.py \
    && ln -sf /usr/local/bin/proxy_wrapper.py /usr/local/bin/git \
    && ln -sf /usr/local/bin/proxy_wrapper.py /usr/local/bin/gh \
    && ln -sf /usr/local/bin/proxy_wrapper.py /usr/local/bin/chmod

# Claude plugin and its python venv
COPY claude-plugin /plugin
ENV PLUGIN_ROOT=/plugin
RUN bash /docker-scripts/create-venv-docker.sh

# Save the host arch once (uname -m output). Each tool's install below
# picks the correct release URL in an explicit case per arch.
RUN echo "ARCH=$(uname -m)" > /etc/arch.env

# act for workflow testing + dispatch wrapper
RUN . /etc/arch.env \
    && case "$ARCH" in \
         x86_64)  curl -sL https://github.com/nektos/act/releases/download/v0.2.87/act_Linux_x86_64.tar.gz | tar -xz -C /usr/local/bin act ;; \
         aarch64) curl -sL https://github.com/nektos/act/releases/download/v0.2.87/act_Linux_arm64.tar.gz  | tar -xz -C /usr/local/bin act ;; \
         *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
       esac \
    && mv /usr/local/bin/act /usr/local/bin/act-real \
    && cp /docker-scripts/act-dispatch-workflow.sh /usr/local/bin/act \
    && chmod +x /usr/local/bin/act

# actionlint for static GitHub Actions workflow linting
RUN . /etc/arch.env \
    && case "$ARCH" in \
         x86_64)  curl -sL https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz | tar -xz -C /usr/local/bin actionlint ;; \
         aarch64) curl -sL https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz | tar -xz -C /usr/local/bin actionlint ;; \
         *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
       esac \
    && chmod +x /usr/local/bin/actionlint

WORKDIR /workspace
ENV WORKSPACE_ROOT=/workspace
ENV PROJECT_ROOT=/workspace
ENV USERNAME=$USERNAME
ENV CARGO_HOME=/home/$USERNAME/.cargo
ENV PATH="$HOME/.local/bin:$PATH"

USER root

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
