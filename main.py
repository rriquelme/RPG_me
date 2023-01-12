import pygame

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
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
    screen.fill(gray1)

    pygame.draw.rect(screen,grey,(0,0,square_draw[0],square_draw[1]))
    pygame.draw.rect(screen,gray1,(square_draw[0],0,resolution_display[0]-square_draw[0],resolution_display[1]))
    pygame.draw.rect(screen,gray2,(0,square_draw[1],square_draw[0],resolution_display[1]-square_draw[1]))
    pygame.display.flip()

pygame.quit()