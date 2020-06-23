#import random
from random import randint

spam = randint(1,10)
guess = 0
i = 1

while guess != str(spam) and i <= 3:
    print('enter a number between 1-10 ')
    guess = input()
    i = i+1

if i==4:
    print('you did not guess the number. Correct number is ' + str(spam))
else:
    print('you guessed the correct number ' + str(spam))
