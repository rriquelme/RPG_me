import pygame
import json
import os
import datetime

white = (255,255,255)
grey =  (169,169,169)
gray1 =(250,250,250)
gray2 =(240,240,240)
gray3 =(230,230,230)
black = (  0,  0,  0)
blue =  (  0,  0,200)


square_draw = (150,150)
resolution_display = [500,500]
pygame.init()
screen = pygame.display.set_mode(resolution_display)
running = True
picture = pygame.image.load("RR.jpg").convert()
picture = pygame.transform.scale(picture, square_draw)
# Using blit to copy content from one surface to other


screen.fill(gray1)
pygame.draw.rect(screen,grey,(0,0,square_draw[0],square_draw[1]))
screen.blit(picture, (0, 0))
pygame.draw.rect(screen,gray1,(square_draw[0],0,resolution_display[0]-square_draw[0],resolution_display[1]))
pygame.draw.rect(screen,gray2,(0,square_draw[1],square_draw[0],resolution_display[1]-square_draw[1]))

clock = pygame.time.Clock()
input_rect = pygame.Rect(150, 25, 400, 25)
base_font = pygame.font.Font(None, 25)
user_text = ''
save = {}
if os.path.isfile('save_file.json'):
    with open('save_file.json', 'r') as file:
        save = json.load(file)

class inputs_rec():
    def __init__(self,x,y,x1,y1) -> None:
        self.rect = pygame.Rect(x,y,x1,y1)
        pygame.draw.rect(screen, gray3, self.rect)
        pass
user_text = save.get('user')
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
            with open('save_file.json', 'w') as outfile:
                json.dump(save, outfile)

        pygame.draw.rect(screen, gray3, input_rect)
        text_surface = base_font.render(user_text, True, (0, 0, 0))
        screen.blit(text_surface, (input_rect.x+5, input_rect.y+5))

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_BACKSPACE:
                user_text = user_text[:-1]
            else:
                user_text += event.unicode
            save["user"] = user_text


    pygame.display.flip()
    clock.tick(60)


pygame.quit()
