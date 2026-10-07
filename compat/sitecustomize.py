"""
Compatibility shim for DETI -- "Polynomial Time Cryptanalytic Extraction of
Neural Network Models" (CRYPTO 2023), https://github.com/...

The paper's code was written against TensorFlow 2.x / Keras 2.x.  This shim
restores the two Keras-2 APIs it uses, which were removed/changed in Keras 3
(shipped with TensorFlow >= 2.16), so the original source can run unmodified.

Enable it by putting this directory on PYTHONPATH:

    PYTHONPATH=/path/to/deti_shim python -m deti.soe ...

It is a no-op on TensorFlow <= 2.15 / Keras 2.
"""

try:
    import sys as _sys

    import tensorflow as _tf
    import keras as _keras

    # 1) Pre-2.16, `tensorflow.keras` was a real submodule, so
    #    `from tensorflow.keras import layers` worked.  In Keras 3 it is only a
    #    lazy attribute of `tensorflow`, and that import form raises
    #    ModuleNotFoundError.  Re-register the standalone package under the old
    #    name.
    _sys.modules.setdefault("tensorflow.keras", _keras)

    # 2) Keras 2 exposed `layer.output_shape` / `model.output_shape` as tuples.
    #    Keras 3 dropped them in favour of `layer.output.shape` (a TensorShape).
    def _output_shape(self):
        return tuple(self.output.shape)

    if not hasattr(_keras.layers.Layer, "output_shape"):
        _keras.layers.Layer.output_shape = property(_output_shape)
    if not hasattr(_keras.Model, "output_shape"):
        _keras.Model.output_shape = property(_output_shape)

except Exception:  # never break a plain interpreter start-up
    pass
