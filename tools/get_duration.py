from mutagen.mp3 import MP3
import os, sys
p = os.path.join(os.getcwd(), 'assets', 'chama.mp3')
if not os.path.exists(p):
    print('NOT_FOUND', p)
    sys.exit(2)
audio = MP3(p)
print('{:.3f}'.format(audio.info.length))
