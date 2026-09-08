#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

extern void ProbeInstallTrace(void);
extern BOOL ProbeRunMath(id interaction,id recognizer);

static void dumpClass(Class cls) {
    printf("CLASS %s : %s\n", class_getName(cls), class_getName(class_getSuperclass(cls)));
    unsigned int n=0;
    Ivar *ivars=class_copyIvarList(cls,&n);
    for(unsigned i=0;i<n;i++) printf(" IVAR %s %s offset=%td\n",ivar_getName(ivars[i]),ivar_getTypeEncoding(ivars[i]),ivar_getOffset(ivars[i]));
    free(ivars);
    Method *methods=class_copyMethodList(cls,&n);
    for(unsigned i=0;i<n;i++) {
        IMP imp=method_getImplementation(methods[i]);
        Dl_info info={0}; dladdr((void *)imp,&info);
        printf(" METHOD %s %s imp=%p image=%s offset=0x%lx\n",sel_getName(method_getName(methods[i])),method_getTypeEncoding(methods[i]),imp,info.dli_fname ?: "",(unsigned long)((char *)imp-(char *)info.dli_fbase));
    }
    free(methods);
    fflush(stdout);
}
static void dumpRuntime(void) {
    for(NSString *name in @[@"_UIKeyboardTextSelectionInteraction",@"_UIKeyboardTextSelectionGestureController",@"_UIKeyboardBasedTextSelectionInteraction",@"_UIKeyboardTextSelectionController",@"_UITextFloatingCursorSession",@"_UITextSelectionSettings",@"_UICubicPolyTangent",@"UITextMagnifierTimeWeightedPoint"]) {
        Class cls=NSClassFromString(name);
        if(cls)dumpClass(cls);
    }
}
static UIGestureRecognizer *nativeSpaceGesture(void) {
    id impl=((id(*)(id,SEL))objc_msgSend)((id)NSClassFromString(@"UIKeyboardImpl"),sel_registerName("sharedInstance"));
    UIView *layout=((id(*)(id,SEL))objc_msgSend)(impl,sel_registerName("layout"));
    for(UIGestureRecognizer *gesture in layout.gestureRecognizers) {
        if([gesture.name isEqualToString:@"_UIKeyboardTextSelectionGestureLongPress"])return gesture;
    }
    return nil;
}
@interface ProbeDelegate : UIResponder <UIApplicationDelegate, UITextViewDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UITextView *editor;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.systemBackgroundColor;
    self.editor=[[UITextView alloc] initWithFrame:CGRectMake(20,100,360,430)];
    self.editor.font=[UIFont systemFontOfSize:22];
    self.editor.text=@"Native cursor investigation.\nThe quick brown fox jumps over the lazy dog. This sentence wraps across several displayed lines.\nРусский текст: ө ү ё.\nEmoji: 👨‍👩‍👧‍👦 🇲🇳 é.\nFinal line for cursor movement.";
    self.editor.delegate=self; self.editor.autocorrectionType=UITextAutocorrectionTypeNo;
    [vc.view addSubview:self.editor]; self.window.rootViewController=vc; [self.window makeKeyAndVisible];
    [self.editor becomeFirstResponder];
    BOOL verify=[NSProcessInfo.processInfo.arguments containsObject:@"--verify"];
    BOOL trace=[NSProcessInfo.processInfo.arguments containsObject:@"--trace"];
    BOOL dump=[NSProcessInfo.processInfo.arguments containsObject:@"--dump-runtime"];
    __block int attempts=0;
    [NSTimer scheduledTimerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer) {
        UIGestureRecognizer *gesture=nativeSpaceGesture();
        if(!gesture && ++attempts<200)return;
        [timer invalidate];
        if(!gesture) {
            fprintf(stderr,"PROBE_ERROR Native Space recognizer unavailable; select Apple's keyboard in this simulator.\n");
            if(verify)exit(1);
            return;
        }
        if(dump)dumpRuntime();
        if(trace)ProbeInstallTrace();
        if(verify) {
            BOOL passed=ProbeRunMath(gesture.delegate,gesture);
            exit(passed?0:1);
        }
        printf("PROBE_READY recognizer=%s\n",gesture.description.UTF8String);fflush(stdout);
    }];
    return YES;
}
- (void)textViewDidChangeSelection:(UITextView *)textView {
    CGRect rect=[textView caretRectForPosition:textView.selectedTextRange.end];
    printf("SELECTION t=%.6f range=%s caret=%s\n",CACurrentMediaTime(),NSStringFromRange(textView.selectedRange).UTF8String,NSStringFromCGRect(rect).UTF8String); fflush(stdout);
}
@end
int main(int argc,char **argv) { @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeDelegate.class));} }
