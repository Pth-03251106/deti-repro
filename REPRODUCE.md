# 运行手册（DETI）

**这份文档只讲"怎么跑"。** 复现做了什么、每个实验的结果与偏差分析，看 [README.md](README.md)。
这里是原论文代码的复现，论文信息与出处见 README 开头。原始英文说明保留在
[README_upstream.md](README_upstream.md)。

---

## 1. 环境准备

必须用 **Keras 2**。Keras 3（TensorFlow ≥ 2.16 自带）删掉了代码依赖的两个 API，直接跑会报
`ModuleNotFoundError: No module named 'tensorflow.keras'`。

```bash
conda create -n deti python=3.11 -y
conda activate deti
pip install -r requirements.txt
```

[requirements.txt](requirements.txt) 锁定：TensorFlow 2.15.0 / Keras 2.15.0 / NumPy 1.26.4 /
pandas 2.2.3 / tabulate 0.10.0 / h5py 3.16.0。

> 安装时若不加 `--only-binary=:all:`，pip 会去源码编译 `cryptography`（需要 Rust 工具链）并挂死
> 十几分钟。

**只有 TensorFlow ≥ 2.16**：[compat/sitecustomize.py](compat/sitecustomize.py) 会把 Keras 2 的两个
API 补回来，`run_deti.sh` 已自动把它加进 `PYTHONPATH`，无需额外操作。

**精度要求**：攻击假设无限精度，实践上要求模型权重是 `float64`。本仓库的模型都满足；换自己的模型
前请先确认 `model.weights[0].dtype` 是 `float64`。

### 关于包名（最容易踩的坑）

代码内部用的是 `from deti.blackbox import ...` 这类**包内绝对导入**，所以必须以名为 `deti` 的包来
运行。但 `deti-main`、`deti-repro` 这种带连字符的目录名不是合法的 Python 标识符。

[run_deti.sh](run_deti.sh) 已经处理好了：它把仓库软链接到一个临时目录下的 `deti` 并设好
`PYTHONPATH`，**不管你 clone 出来的目录叫什么名字都能跑**。直接用它就行。

想手动跑的话，需要自己造这个软链接：

```bash
# 假设仓库在 /path/to/deti-repro
mkdir -p /tmp/pkgroot
ln -s /path/to/deti-repro /tmp/pkgroot/deti
cd /path/to/deti-repro
PYTHONPATH=/tmp/pkgroot:/path/to/deti-repro/compat python3 -m deti.soe --model models/... --layerID 1
```

### CIFAR10 数据集

只有实验 7 的 Neuron Wiggle（`--dataset CIFAR10`）需要它。Keras 默认从 `cs.toronto.edu` 下载，
国内实测仅 ~90 KB/s（170 MB 需一个多小时）。可改用百度镜像（~470 KB/s，约 6 分钟）并校验 SHA256：

```bash
# SHA256 须为 6d958be074577803d12ecdefd02955f39262c83c16fe9348329d7fe0b5c001ce
curl -L -o ~/.keras/datasets/cifar-10-batches-py.tar.gz \
  https://dataset.bj.bcebos.com/cifar/cifar-10-python.tar.gz
```

---

## 2. 怎么跑

论文 README 列出的 8 个实验，逐条对应：

```bash
./run_deti.sh soe          --model models/unitary_784_128_1.h5    --layerID 1 --runID soe
./run_deti.sh lastLayer    --model models/unitary_784_128_1.h5    --layerID 1 --runID lastLayer

./run_deti.sh neuronWiggle --model models/unitary_100_200x3_10.h5 --layerID 1 \
                           --runID neuronWiggle --tgtNeurons 4 26 30 77 168
./run_deti.sh neuronWiggle --model models/unitary_100_200x3_10.h5 --layerID 2 \
                           --runID neuronWiggle --tgtNeurons 4 26 30 77 168
./run_deti.sh lastLayer    --model models/unitary_100_200x3_10.h5 --layerID 3 --runID lastLayer

./run_deti.sh soe          --model models/cifar10_rgb_8x256.h5    --layerID 1 --runID soe
./run_deti.sh neuronWiggle --model models/cifar10_rgb_8x256.h5    --layerID 2 \
                           --runID neuronWiggle --dataset CIFAR10 --tgtNeurons 4 26 30 77 168
./run_deti.sh lastLayer    --model models/cifar10_rgb_8x256.h5    --layerID 8 --runID lastLayer
```

`python3` 不是你要用的解释器时，用 `DETI_PYTHON` 指定：

```bash
DETI_PYTHON=/opt/anaconda3/envs/deti/bin/python ./run_deti.sh soe ...
```

**看结果**：跑到一半中断也可以，结果会实时写入 `results/`，读法见
[README 附录](README.md#附录目录与结果文件说明)。要复现哪一项、预期耗时多少，对照
[README 第四节的结果汇总表](README.md#四结果汇总)——注意 `neuronWiggle` 未并行化，**整项跑完约需
数十分钟到数小时**（实验 7 单神经元就要 335 s）。

### `--layerID` 的含义

**从 1 开始，跳过 InputLayer**（见 [whitebox.py:20](whitebox.py#L20)）。所以 `unitary_100_200x3_10`
的 `layerID 3` 是它的最后一个隐层，`cifar10_rgb_8x256` 的 `layerID 8` 是最后一个隐层——这也是
`lastLayer` 方法要攻击的层。

### `neuronWiggle` 的 `--tgtNeurons`

该实现**逐个神经元串行**且未并行化，所以论文的演示也只抽 5 个神经元（4, 26, 30, 77, 168）。
不传这个参数时的行为见 [common.py:63](common.py#L63) 的默认值。

---

## 3. 跑出问题时的排查

| 现象 | 原因 / 处理 |
|---|---|
| `ModuleNotFoundError: No module named 'deti'` | 没通过 `run_deti.sh` 跑，或没用包名 `deti`。见第 1 节。 |
| `No module named 'tensorflow.keras'` | 用了 Keras 3（TF ≥ 2.16）。降级到 TF 2.15，或确保 `compat/` 在 `PYTHONPATH` 上。 |
| `PRECISION ERROR(1)/(3)` | 数值精度不够。`lastLayer` 可试调 `--eps`（建议 3 < eps < 8）。 |
| `LINEARITY ERROR: try increasing --eps` | 同上，调大 `--eps`。 |
| 结果与 `results/` 里的不完全一致 | 正常。`neuronWiggle` 的采样和随机初始点是随机的，耗时也随机器变化；**判据是正确率**（`isCorrect` / `isRecoveredCorrectly`）。 |
| `neuronWiggle` 特别慢 | 正常，该实现未并行化。论文指出有明显可并行点，见 [README_upstream.md](README_upstream.md) 的 Implementation Status 一节。 |
| 想跑自己的模型 | 需为 `float64`，且最后一层激活必须是 linear（脚本会自动改回并打印 warning）。 |
