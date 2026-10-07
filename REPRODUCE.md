# 复现说明（DETI）

本仓库是对下面这篇论文所发布代码的**复现**，包含一份可移植的运行脚本、锁定的依赖版本，以及复现跑出的 `results/`。

> Isaac A. Canales-Martínez, Jorge Chávez-Saab, Anna Hambitzer,
> Francisco Rodríguez-Henríquez, Nitin Satpute, Adi Shamir.
> *Polynomial Time Cryptanalytic Extraction of Neural Network Models.*
> [Cryptology ePrint Archive 2023/1526](https://eprint.iacr.org/2023/1526) ·
> [arXiv:2310.08708](https://arxiv.org/abs/2310.08708) ·
> EUROCRYPT 2024, LNCS 14653, pp. 3–33,
> [DOI 10.1007/978-3-031-58734-4_1](https://doi.org/10.1007/978-3-031-58734-4_1)

原始代码以 MIT 协议发布（见 [LICENSE](LICENSE)，版权归原作者所有），本仓库沿用同一协议。

> 注：原 `README.md` 中写的是 "CRYPTO 2023"，但该论文实际发表于 EUROCRYPT 2024；
> ePrint 2023/1526 是 2023 年的预印本。以 EUROCRYPT 2024 为准。

---

## 1. 这个攻击在做什么

给定一个 ReLU 网络的**黑盒**（只能查询输入输出），在多项式时间内恢复其全部实值参数。
论文提出三种**符号恢复**技术，本仓库各有一个脚本：

| 脚本 | 技术 | 原理 |
|---|---|---|
| [soe.py](soe.py) | SOE | 用一阶导构造线性方程组求解 |
| [neuronWiggle.py](neuronWiggle.py) | Neuron Wiggle | 统计扰动输入后输出的变化 |
| [lastLayer.py](lastLayer.py) | Last Hidden Layer | 用二阶导恢复输出层系数 |

脚本会顺带调用 [whitebox.py](whitebox.py) 读取真实权重得到符号真值，用来对照黑盒恢复结果是否正确——
所以这些脚本**既做攻击也做打分**。

---

## 2. 环境准备

必须用 **Keras 2**。Keras 3（TensorFlow ≥ 2.16 自带）删掉了代码依赖的两个 API，直接跑会报
`ModuleNotFoundError: No module named 'tensorflow.keras'`。

```bash
conda create -n deti python=3.11 -y
conda activate deti
pip install -r requirements.txt
```

`requirements.txt` 锁定的版本：TensorFlow 2.15.0 / Keras 2.15.0 / NumPy 1.26.4 / pandas 2.2.3 /
tabulate 0.10.0 / h5py 3.16.0。

**如果你只有 TensorFlow ≥ 2.16**：仓库里的 [compat/sitecustomize.py](compat/sitecustomize.py)
会把 Keras 2 的两个 API 补回来，`run_deti.sh` 已经自动把它加进 `PYTHONPATH`，无需额外操作。

**精度要求**：攻击假设无限精度，实践上要求模型权重是 `float64`。本仓库的模型都满足；
自己换模型时请先确认 `model.weights[0].dtype` 是 `float64`。

### 关于包名（最容易踩的坑）

代码内部用的是 `from deti.blackbox import ...` 这类**包内绝对导入**，所以必须以名为 `deti`
的包来运行。但 `deti-main`、`deti-repro` 这种带连字符的目录名不是合法的 Python 标识符。

[run_deti.sh](run_deti.sh) 已经处理好了：它把仓库软链接到一个临时目录下的 `deti` 并设好
`PYTHONPATH`，**不管你 clone 出来的目录叫什么名字都能跑**。直接用它就行。

想手动跑的话，需要自己造这个软链接：

```bash
# 假设仓库在 /path/to/deti-repro
ln -s /path/to/deti-repro /tmp/pkgroot/deti
cd /path/to/deti-repro
PYTHONPATH=/tmp/pkgroot:/path/to/deti-repro/compat python3 -m deti.soe --model models/... --layerID 1
```

---

## 3. 怎么跑

```bash
./run_deti.sh soe          --model models/unitary_784_128_1.h5   --layerID 1 --runID soe
./run_deti.sh lastLayer    --model models/unitary_784_128_1.h5   --layerID 1 --runID lastLayer
./run_deti.sh soe          --model models/cifar10_rgb_8x256.h5   --layerID 1 --runID soe
./run_deti.sh lastLayer    --model models/cifar10_rgb_8x256.h5   --layerID 8 --runID lastLayer
./run_deti.sh lastLayer    --model models/unitary_100_200x3_10.h5 --layerID 3 --runID lastLayer

# neuronWiggle 未并行化，只对少数神经元抽样跑（--tgtNeurons 指定）
./run_deti.sh neuronWiggle --model models/unitary_100_200x3_10.h5 --layerID 1 \
                           --runID neuronWiggle --tgtNeurons 4 26 30 77 168
./run_deti.sh neuronWiggle --model models/unitary_100_200x3_10.h5 --layerID 2 \
                           --runID neuronWiggle --tgtNeurons 4 26 30 77 168
./run_deti.sh neuronWiggle --model models/cifar10_rgb_8x256.h5 --layerID 2 \
                           --runID neuronWiggle --dataset CIFAR10 --tgtNeurons 4 26 30 77 168
```

如果 `python3` 不是你要用的解释器，用 `DETI_PYTHON` 指定：

```bash
DETI_PYTHON=/opt/anaconda3/envs/deti/bin/python ./run_deti.sh soe ...
```

### `--layerID` 的含义

**从 1 开始，跳过 InputLayer**（[whitebox.py:20](whitebox.py#L20) 用 `range(1, layerID+1)` 取
`model.layers`）。所以 `unitary_100_200x3_10` 的 `layerID 3` 是它的最后一个隐层，
`cifar10_rgb_8x256` 的 `layerID 8` 是最后一个隐层——这也是 `lastLayer` 方法要攻击的层。

### 预期耗时

单核、与论文机器不同，仅供参考：

| 模型 | 方法 | 神经元数 | 本次耗时 |
|---|---|---|---|
| `unitary_784_128_1` | SOE | 128 | 9.1 s |
| `unitary_784_128_1` | Last Hidden Layer | 128 | 26.1 s |
| `unitary_100_200x3_10` | Last Hidden Layer | 200 | 43.9 s |
| `unitary_100_200x3_10` | Neuron Wiggle | 5（抽样） | ~113 s 总计 / 约 22–27 s 每神经元 |
| `cifar10_rgb_8x256` | SOE | 256 | 17.9 s |
| `cifar10_rgb_8x256` | Last Hidden Layer | 256 | 155.9 s |
| `cifar10_rgb_8x256` | Neuron Wiggle | 5（抽样） | ~1675 s 总计 / 约 324–341 s 每神经元 |

---

## 4. 模型与结果

### `models/`

三个模型，命名规则为 `{输入维度}_{隐层宽度}x{层数}_{输出数}`：

| 模型 | 结构 | 说明 |
|---|---|---|
| `unitary_784_128_1` | 784 → 128 ReLU → 1 linear | 28×28 展平，二分类 |
| `unitary_100_200x3_10` | 100 → 200×3 ReLU → 10 linear | 100 维随机输入，10 类 |
| `cifar10_rgb_8x256` | 3072(32×32×3) → 256×8 ReLU → 10 sigmoid | CIFAR-10，测试准确率 0.5249 |

三点说明：

- **`.h5` 和 `.keras` 是同一份内容的重复副本**（md5 相同），不是不同模型。原因是这两个扩展名
  在本仓库里用途不同：`.keras` 是原仓库的命名，`.h5` 则让 `results/` 下的目录名
  （`model_xxx.h5/`）与现成结果对得上。
- 这些 `.keras` 文件**其实是旧式 HDF5 格式**（Keras 2.7.0 保存），不是 Keras 3 新的 zip 格式，
  所以改扩展名也能加载。
- `unitary` 指**每个神经元的权重向量是单位范数随机向量**，`balanced` 指 bias 取采样中位数使
  神经元约 50% 概率激活（见 [unitarydnn.py](unitarydnn.py)）。**不是**指权重矩阵酉/正交——
  整矩阵奇异值并不为 1。
- CIFAR 模型的输出层用的是 **sigmoid**，三个脚本都会在加载后把最后一层激活**强制改回 linear**
  再攻击（并打印一条 warning），这是预期行为。

### `results/`

目录按 `results/model_{模型}/layerID_{层}/nExp_{次数}/runID_{标签}/` 组织
（见 [common.py:21-32](common.py:21-32)）。每个 runID 下最多三种文件：

| 文件 | 内容 | 读取方式 |
|---|---|---|
| `df.md` | 结果表的 Markdown 渲染，给人看的 | 直接打开 |
| `df.pkl` | 同一个 DataFrame 的 pickle，给程序看的 | `pd.read_pickle(...)` |
| `neuronID_<n>_samples.npz` | 该神经元恢复符号所用的采样点，键为 `samplesL` / `samplesR` | `np.load(...)["samplesL"]` |

`.npz` **只有 neuronWiggle 会产出**，因为它需要记录扰动采样点。

本仓库已经跑完 8 组实验，**全部 100% 正确恢复**：

| 结果目录 | 神经元 | 正确率 |
|---|---|---|
| `model_unitary_784_128_1.h5/layerID_1/.../runID_soe` | 128 | 128/128 |
| `model_unitary_784_128_1.h5/layerID_1/.../runID_lastLayer` | 128 | 128/128 |
| `model_unitary_100_200x3_10.h5/layerID_1/.../runID_neuronWiggle` | 5 | 5/5 |
| `model_unitary_100_200x3_10.h5/layerID_2/.../runID_neuronWiggle_L2` | 5 | 5/5 |
| `model_unitary_100_200x3_10.h5/layerID_3/.../runID_lastLayer` | 200 | 200/200 |
| `model_cifar10_rgb_8x256.h5/layerID_1/.../runID_soe` | 256 | 256/256 |
| `model_cifar10_rgb_8x256.h5/layerID_2/.../runID_neuronWiggle_CIFAR10` | 5 | 5/5 |
| `model_cifar10_rgb_8x256.h5/layerID_8/.../runID_lastLayer` | 256 | 256/256 |

各方法的表格列不同，别混用：`lastLayer`/`soe` 每行是整层的每个神经元（列含
`realSign`/`recoveredSign`/`isCorrect`，`lastLayer` 还多一列 `coeff`）；
`neuronWiggle` 只跑 `--tgtNeurons` 指定的少数神经元，所以只有 5 行
（列含 `metric4Minus`/`metric4Plus`/`percentage`/`tFoundCrit`/`tSignRec`）。

---

## 5. 跑出问题时的排查

| 现象 | 原因 / 处理 |
|---|---|
| `ModuleNotFoundError: No module named 'deti'` | 没通过 `run_deti.sh` 跑，或没用包名 `deti`。见第 2 节。 |
| `No module named 'tensorflow.keras'` | 用了 Keras 3（TF ≥ 2.16）。降级到 TF 2.15，或确保 `compat/` 在 `PYTHONPATH` 上。 |
| `PRECISION ERROR(1)/(3)` | 数值精度不够。`lastLayer` 可试 `--eps` 调整（建议 3 < eps < 8）。 |
| `LINEARITY ERROR: try increasing --eps` | 同上，调大 `--eps`。 |
| 结果与 `results/` 里的不完全一致 | 正常。`neuronWiggle` 的采样和随机初始点是随机的，耗时也随机器变化；**判据是正确率**（`isCorrect` / `isRecoveredCorrectly`）。 |
| `neuronWiggle` 特别慢 | 正常，该实现未并行化。论文指出有明显可并行点，见原 `README.md` 的 Implementation Status 一节。 |
