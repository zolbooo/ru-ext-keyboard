#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
static id get(id o,const char*s){return ((id(*)(id,SEL))objc_msgSend)(o,sel_registerName(s));}
static id arg(id o,const char*s,id a){return ((id(*)(id,SEL,id))objc_msgSend)(o,sel_registerName(s),a);}
static void keys(id tree,id layout){
 NSString *s=get(tree,"representedString");
 if(s.length){ unsigned long f=((unsigned long(*)(id,SEL,id))objc_msgSend)(layout,sel_registerName("upActionFlagsForKey:"),tree); printf("KEY %s %s flags=%lx\n",[get(tree,"name") UTF8String],s.UTF8String,f); }
 for(id c in get(tree,"subtrees")) keys(c,layout);
}
@interface App : UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property UITextView *editor;
@end
@implementation App
-(BOOL)application:(UIApplication*)a didFinishLaunchingWithOptions:(NSDictionary*)o{
 freopen([[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/results.txt"] fileSystemRepresentation],"w",stdout);setbuf(stdout,NULL);
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds]; UIViewController *vc=[UIViewController new];self.editor=[[UITextView alloc]initWithFrame:CGRectMake(20,80,350,400)];self.editor.text=@"Test";self.editor.autocorrectionType=UITextAutocorrectionTypeNo;[vc.view addSubview:self.editor];self.window.rootViewController=vc;[self.window makeKeyAndVisible];[self.editor becomeFirstResponder];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 id impl=get(NSClassFromString(@"UIKeyboardImpl"),"activeInstance");id l=get(impl,"layout");printf("LAYOUT %s\n",object_getClassName(l));
 if(![l respondsToSelector:sel_registerName("upActionFlagsForKey:")]){printf("ERROR native keyboard unavailable\n");exit(1);}
 id p=get(l,"keyplane");printf("PLANE %s alternate %s\n",[get(p,"name") UTF8String],[get(p,"alternateKeyplaneName") UTF8String]);
 for(int i=0;i<3;i++){p=get(l,"keyplane");printf("PAGE %s\n",[get(p,"name") UTF8String]);keys(p,l);id next=get(p,i==0?"alternateKeyplaneName":"shiftAlternateKeyplaneName");arg(l,"setKeyplaneName:",next);}
 fflush(stdout);exit(0);
 });return YES;
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
