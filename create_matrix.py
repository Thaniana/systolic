import numpy as np


I = np.identity(16)

for j in range(16):
    for i in range(16):
        print(int(I[j][i])) 