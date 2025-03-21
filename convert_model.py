import keras
import tensorflow as tf
import numpy as np
import os   

model = keras.Sequential([  # Instead of tf.keras.Sequential
    keras.layers.Input(shape=(160, 160, 3)),
    keras.layers.Conv2D(32, 3, activation='relu'),
    keras.layers.MaxPooling2D(),
    keras.layers.Conv2D(64, 3, activation='relu'),
    keras.layers.MaxPooling2D(),
    keras.layers.Conv2D(64, 3, activation='relu'),
    keras.layers.Flatten(),
    keras.layers.Dense(128, activation=None),
    keras.layers.Lambda(lambda x: tf.nn.l2_normalize(x, axis=1))

])


# Convert the model to TFLite format
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

# Ensure the assets directory exists
os.makedirs('assets', exist_ok=True)

# Save the TFLite model
tflite_model_path = 'assets/facenet_model.tflite'
with open(tflite_model_path, 'wb') as f:
    f.write(tflite_model)

print(f"✅ TFLite model successfully saved at: {tflite_model_path}")
