
class Skill(object):
    def __init__(self, name : str) -> None:
        self.name = name
        self.level = 0

    def level_set(self, level : int) -> None:
        self.level =  level

    def level_up(self) -> None:
        self.level += 1

class Lvl_char (object):
    def __init__(self) -> None:
        self.exp = 0
        self.lvl = 1
        self.exp_next = 50
        self.base_exp_per_level = 50
    def gain_exp(self, exp : int):
        self.exp += exp
        if self.exp >= self.exp_next:
            self.exp -= self.exp_next
            self.lvl += 1
            self.exp_next = (self.lvl * self.base_exp_per_level * 2** (self.lvl - 1) )
    