#import <UIKit/UIKit.h>

@interface SPDViewController : UIViewController
@end

@implementation SPDViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.clearColor;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = CGRectMake(0, 0, 60, 60);
    button.center = self.view.center;

    button.backgroundColor =
        [UIColor colorWithRed:0.85
                        green:0.20
                         blue:0.20
                        alpha:0.95];

    button.layer.cornerRadius = 30.0;
    button.clipsToBounds = YES;

    [button setTitle:@"SPD"
            forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                  forState:UIControlStateNormal];

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:14.0];

    [button addTarget:self
               action:@selector(spdButtonClicked:)
     forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:button];
}

- (void)spdButtonClicked:(UIButton *)sender {

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"SpeedTweak"
            message:@"SPD 按钮点击成功\n\n当前为诊断模式，暂未安装 Hook。"
            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"确定"
                      style:UIAlertActionStyleDefault
                    handler:nil]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

@end


@interface SPDWindow : UIWindow
@end

@implementation SPDWindow

- (BOOL)pointInside:(CGPoint)point
          withEvent:(UIEvent *)event {

    return [super pointInside:point withEvent:event];
}

@end


static SPDWindow *g_spdWindow = nil;


static UIWindowScene *GetActiveWindowScene(void)
{
    if (@available(iOS 13.0, *)) {

        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateForegroundActive) {

                return windowScene;
            }
        }

        // 如果没有 ForegroundActive，
        // 再尝试寻找 ForegroundInactive
        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateForegroundInactive) {

                return windowScene;
            }
        }
    }

    return nil;
}


static void CreateSPDWindow(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (g_spdWindow != nil) {

            g_spdWindow.hidden = NO;
            return;
        }

        UIWindowScene *scene = GetActiveWindowScene();

        if (@available(iOS 13.0, *)) {

            if (scene == nil) {

                NSLog(@"[CDTweak] 找不到 UIWindowScene");

                return;
            }

            g_spdWindow =
                [[SPDWindow alloc]
                    initWithWindowScene:scene];

        } else {

            g_spdWindow =
                [[SPDWindow alloc]
                    initWithFrame:CGRectMake(
                        20,
                        120,
                        80,
                        80)];
        }

        g_spdWindow.frame =
            CGRectMake(20, 120, 80, 80);

        g_spdWindow.backgroundColor =
            UIColor.clearColor;

        /*
         * 比普通 Alert Window 高，
         * 同时避免使用过于极端的 windowLevel。
         */
        g_spdWindow.windowLevel =
            UIWindowLevelAlert + 1.0;

        SPDViewController *vc =
            [[SPDViewController alloc] init];

        g_spdWindow.rootViewController = vc;

        g_spdWindow.hidden = NO;

        /*
         * 强制显示
         */
        [g_spdWindow makeKeyAndVisible];

        /*
         * 不抢宿主 App 的 KeyWindow。
         * 延迟一点恢复。
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{

                [g_spdWindow resignKeyWindow];
            });

        NSLog(@"[CDTweak] SPD Window 创建成功");

    });
}
