import pygame

white = (255,255,255)
grey =  (169,169,169)
black = (  0,  0,  0)
blue =  (  0,  0,200)
pygame.init()
screen = pygame.display.set_mode([500, 500])
running = True
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
    screen.fill(grey)
    #pygame.draw.circle(screen, (0, 0, 255), (250, 250), 75)
    pygame.draw.rect(screen,blue,(50,50,100,100))
    pygame.display.flip()

pygame.quit()