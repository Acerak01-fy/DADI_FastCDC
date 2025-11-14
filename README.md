# 构建说明

本指南将帮助您配置和运行 overlaybd 镜像服务的常规使用场景。

- [构建说明](#构建说明)
  - [安装](#安装)
    - [overlaybd-snapshotter](#overlaybd-snapshotter)
      - [源码编译](#源码编译)
      - [配置](#配置)
      - [启动服务](#启动服务)
    - [overlaybd-tcmu](#overlaybd-tcmu)
      - [从源码编译](#从源码编译)
      - [配置](#配置-1)
      - [启动服务](#启动服务-1)
  - [系统配置](#系统配置)
    - [Containerd](#containerd)
    - [认证](#认证)
  - [运行 overlaybd 镜像](#运行-overlaybd-镜像)
  - [镜像转换](#镜像转换)
  - [备注](#备注)

## 安装

需要配置两个组件：`overlaybd-snapshotter` 和 `overlaybd-tcmu`。它们分别位于当前代码仓库中/overlaybd以及/Accelerated_Container_Imag中。


### overlaybd-snapshotter


#### 源码编译

安装依赖：
- golang 1.22+

运行以下命令进行构建：
```bash
#git clone https://github.com/containerd/accelerated-container-image.git 也可以在原仓库拉取，DADI的这部分未作修改
cd Accelerated_Container_Image
make
sudo make install
```


#### 配置
配置文件位于 `/etc/overlaybd-snapshotter/config.json`。如果文件不存在，请创建它。我们建议将 snapshotter 的根路径设置为 containerd 根路径的一个子路径。

```json
{
    "root": "/var/lib/containerd/io.containerd.snapshotter.v1.overlaybd",
    "address": "/run/overlaybd-snapshotter/overlaybd.sock",
    "verbose": "info",
    "rwMode": "overlayfs",
    "logReportCaller": false,
    "autoRemoveDev": false,
    "exporterConfig": {
        "enable": false,
        "uriPrefix": "/metrics",
        "port": 9863
    },
    "mirrorRegistry": [
        {
            "host": "localhost:5000",
            "insecure": true
        },
        {
            "host": "registry-1.docker.io",
            "insecure": false
        }
    ]
}
```

| 字段 | 描述 |
|---|---|
| `root` | 存储快照的根目录。建议：此路径应为 containerd 根目录的子路径。 |
| `address` | 用于与 containerd 连接的 socket 地址。 |
| `verbose` | 日志级别，`info` 或 `debug`。 |
| `rwMode` | rootfs 模式，关于是否使用原生可写层。详情请见“原生可写支持”。 |
| `logReportCaller` | 启用/禁用调用方法日志。 |
| `autoRemoveDev` | 启用/禁用在容器移除后自动清理 overlaybd 设备。 |
| `exporterConfig.enable` | 是否创建一个服务器以展示 Prometheus 指标。 |
| `exporterConfig.uriPrefix` | 导出指标的 URI 前缀，默认为 `/metrics`。 |
| `exporterConfig.port` | 用于展示指标的 http 服务器端口，默认为 9863。 |
| `mirrorRegistry` | 镜像仓库的数组。 |
| `mirrorRegistry.host` | 主机地址，例如 `registry-1.docker.io`。 |
| `mirrorRegistry.insecure` | `true` 或 `false`。 |

#### 启动服务
直接运行 `/opt/overlaybd/snapshotter/overlaybd-snapshotter` 二进制文件，或者通过添加到systemctl启动 `overlaybd-snapshotter.service` 来作为服务运行。

如果从源码安装，请运行以下命令启动服务：
```bash
sudo systemctl enable /opt/overlaybd/snapshotter/overlaybd-snapshotter.service
sudo systemctl start overlaybd-snapshotter
```

### overlaybd-tcmu


<!-- > **注意**：`overlaybd-snapshotter` 和 `overlaybd-tcmu` 的版本之间没有强依赖关系。但是，`overlaybd-snapshotter v1.0.1+` 需要 `overlaybd-tcmu v1.0.4+`，因为镜像转换的参数有所调整。 -->

#### 从源码编译

安装依赖：
- cmake 3.15+
- gcc/g++ 7+
- 开发依赖：
  - **CentOS 7/Fedora**: `sudo yum install libaio-devel libcurl-devel openssl-devel libnl3-devel libzstd-static e2fsprogs-devel`
  - **CentOS 8**: `sudo yum install libaio-devel libcurl-devel openssl-devel libnl3-devel libzstd-devel e2fsprogs-devel`
  - **Debian/Ubuntu**: `sudo apt install libcurl4-openssl-dev libssl-dev libaio-dev libnl-3-dev libnl-genl-3-dev libgflags-dev libzstd-dev libext2fs-dev`

运行以下命令进行构建：
```bash
cd overlaybd
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j
sudo make install
```


#### 配置
配置文件位于 `/etc/overlaybd/overlaybd.json`。如果通过包管理器安装，会自动生成默认配置，可以直接使用无需更改。


#### 启动服务
```bash
sudo systemctl enable /opt/overlaybd/overlaybd-tcmu.service
sudo systemctl start overlaybd-tcmu
```

## 系统配置

### Containerd
需要 `containerd 1.4+` 版本。

将 snapshotter 配置添加到 containerd 的配置文件中（默认为 `/etc/containerd/config.toml`）。
```toml
[proxy_plugins.overlaybd]
    type = "snapshot"
    address = "/run/overlaybd-snapshotter/overlaybd.sock"
```

如果使用 k8s/cri，请添加以下配置：
```toml
[plugins.cri]
    [plugins.cri.containerd]
        snapshotter = "overlaybd"
        disable_snapshot_annotations = false
```
确保 `cri` 没有在 containerd 配置文件的 `disabled_plugins` 列表中。

最后，不要忘记重启 containerd 服务。

### 认证
由于 `containerd` 和 `overlaybd-tcmu` 之间无法共享认证信息，因此必须为 `overlaybd-tcmu` 单独配置认证。

`overlaybd-tcmu` 的认证配置文件路径可以在 `/etc/overlaybd/overlaybd.json` 中指定（默认为 `/opt/overlaybd/cred.json`）。

这是一个示例，其格式与 Docker 的认证文件（`/root/.docker/config.json`）相同：
```json
{
  "auths": {
    "hub.docker.com": {
      "username": "username",
      "password": "password"
    },
    "hub.docker.com/hello/world": {
      "auth": "dXNlcm5hbWU6cGFzc3dvcmQK"
    }
  }
}
```

## 运行 overlaybd 镜像
现在用户可以运行 overlaybd 格式的镜像了。有以下几种方法：

**使用 `nerdctl`**
```bash
sudo nerdctl run --net host -it --rm --snapshotter=overlaybd registry.hub.docker.com/overlaybd/redis:6.2.1_obd
```

**使用 `rpull`**
```bash
# 使用 rpull 拉取镜像，但不会下载层数据
sudo /opt/overlaybd/snapshotter/ctr rpull -u {user}:{pass} registry.hub.docker.com/overlaybd/redis:6.2.1_obd

# 使用 ctr run 运行容器
sudo ctr run --net-host --snapshotter=overlaybd --rm -t registry.hub.docker.com/overlaybd/redis:6.2.1_obd demo
```


## 镜像转换
有两种方法可以将 OCI 格式的镜像转换为 overlaybd 格式：使用内嵌的 `image-convertor` 或使用独立的用户空间 `image-convertor`。

**使用内嵌的 `image-convertor`**
```bash
# 拉取源镜像 (使用 nerdctl 或 ctr)
sudo nerdctl pull registry.hub.docker.com/library/redis:7.2.3

# 转换
sudo /opt/overlaybd/snapshotter/ctr obdconv registry.hub.docker.com/library/redis:7.2.3 registry.hub.docker.com/overlaybd/redis:7.2.3_obd_new

# 将 overlaybd 镜像推送到镜像仓库，之后新的转换后镜像就可以作为远程镜像使用
sudo nerdctl push registry.hub.docker.com/overlaybd/redis:7.2.3_obd_new

# 移除本地的 overlaybd 镜像
sudo nerdctl rmi registry.hub.docker.com/overlaybd/redis:7.2.3_obd_new
```

**使用独立的用户空间 `image-convertor`**
```bash
# userspace-image-convertor 会自动从镜像仓库拉取和推送镜像
sudo /opt/overlaybd/snapshotter/convertor -r registry.hub.docker.com/library/redis -i 6.2.1 -o 6.2.1_obd_new
```

## 备注
由于DADI最新引入的ibphoton(https://photonlibos.github.io/cn/docs/category/introduction)的网络库，这个库是不支持http_proxy的变量的，所以设置代理没有用，run的时候是由overlaybd-tcmu去发请求，所以即使把containerd，ctr，overlaybd-tcmu, overlaybd-snapshotter全部加上http_proxy的环境变量也都没有用，运行的时候会获取blob失败。
因此本次实验采用的是局域网内不同主机之间做测试，采用的是一台主机做registry，另一台主机来做冷启动实验。目的是解决校园网访问dockerhub仓库存在的网络问题。并且这种情况需要为registry主机申请https自签名证书走https协议传输。才能成功。
