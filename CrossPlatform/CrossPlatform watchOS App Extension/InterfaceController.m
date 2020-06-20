//
//  InterfaceController.m
//  CrossPlatform watchOS App Extension
//
//  Created by panwei on 2020/6/20.
//  Copyright © 2020 WeirdPan. All rights reserved.
//

#import "InterfaceController.h"
#import "GameScene.h"

@interface InterfaceController ()

@property (strong, nonatomic) IBOutlet WKInterfaceSKScene *skInterface;

@end


@implementation InterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];

    GameScene *scene = [GameScene newGameScene];
    
    // Present the scene
    [self.skInterface presentScene:scene];
    
    // Use a preferredFramesPerSecond that will maintain consistent frame rate
    self.skInterface.preferredFramesPerSecond = 30;
}

- (void)willActivate {
    // This method is called when watch view controller is about to be visible to user
    [super willActivate];
}

- (void)didDeactivate {
    // This method is called when watch view controller is no longer visible
    [super didDeactivate];
}

@end
