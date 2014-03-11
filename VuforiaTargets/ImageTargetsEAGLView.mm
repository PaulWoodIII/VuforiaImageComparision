/*==============================================================================
 Copyright (c) 2012-2013 Qualcomm Connected Experiences, Inc.
 All Rights Reserved.
 ==============================================================================*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>

#import <QCAR/QCAR.h>
#import <QCAR/State.h>
#import <QCAR/Tool.h>
#import <QCAR/Renderer.h>
#import <QCAR/TrackableResult.h>
#import <QCAR/VideoBackgroundConfig.h>

#import "ImageTargetsEAGLView.h"
#import "SampleApplicationUtils.h"

#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

//******************************************************************************
// *** OpenGL ES thread safety ***
//
// OpenGL ES on iOS is not thread safe.  We ensure thread safety by following
// this procedure:
// 1) Create the OpenGL ES context on the main thread.
// 2) Start the QCAR camera, which causes QCAR to locate our EAGLView and start
//    the render thread.
// 3) QCAR calls our renderFrameQCAR method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************


@interface ImageTargetsEAGLView (PrivateMethods)

- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;

@end

QCAR::Vec2F cameraPointToScreenPoint(QCAR::Vec2F cameraPoint);

@implementation ImageTargetsEAGLView

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app
{
    self = [super initWithFrame:frame];

    if (self) {
        vapp = app;
        // Enable retina mode if available on this device
        if (YES == [vapp isRetinaDisplay]) {
            [self setContentScaleFactor:2.0f];
        }

        // Create the OpenGL ES context
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (context != [EAGLContext currentContext]) {
            [EAGLContext setCurrentContext:context];
        }

        self.targetName = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 40)];
        self.targetName.text = @"error";
        self.targetName.textColor = [UIColor greenColor];
        self.targetName.backgroundColor = [UIColor whiteColor];
        
        [self createEmmitter];
        
        offTargetTrackingEnabled = NO;
        
    }
    
    return self;
}


- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];
    [_targetName release];

    [super dealloc];
}


- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (context) {
        [EAGLContext setCurrentContext:context];
        glFinish();
    }
}


- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}

- (void) setOffTargetTrackingMode:(BOOL) enabled {
    offTargetTrackingEnabled = enabled;
}

//------------------------------------------------------------------------------
#pragma mark - UIGLViewProtocol methods


- (CGPoint) projectCoord:(CGPoint)coord
                  inView:(const QCAR::CameraCalibration&)cameraCalibration
                 andPose:(QCAR::Matrix34F)pose
              withOffset:(CGPoint)offset
                andScale:(CGFloat)scale
{
    CGPoint converted;
    
    QCAR::Vec3F vec(coord.x,coord.y,0);
    QCAR::Vec2F sc = QCAR::Tool::projectPoint(cameraCalibration, pose, vec);
    converted.x = sc.data[0]*scale - offset.x;
    converted.y = sc.data[1]*scale - offset.y;
    
    return converted;
}

QCAR::Vec2F cameraPointToScreenPoint(QCAR::Vec2F cameraPoint)
{
    QCAR::VideoMode videoMode = QCAR::CameraDevice::getInstance().getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
    QCAR::VideoBackgroundConfig config = QCAR::Renderer::getInstance().getVideoBackgroundConfig();
    int xOffset = ((int) 320 - config.mSize.data[0]) / 2.0f + config.mPosition.data[0];
    int yOffset = ((int) 568 - config.mSize.data[1]) / 2.0f - config.mPosition.data[1];
    if (YES) { // camera image is rotated 90 degrees
        int rotatedX = videoMode.mHeight - cameraPoint.data[1];
        int rotatedY = cameraPoint.data[0];
        return QCAR::Vec2F(rotatedX * config.mSize.data[0] / (float) videoMode.mHeight + xOffset,
                           rotatedY * config.mSize.data[1] / (float) videoMode.mWidth + yOffset);
    }
    else {
        return QCAR::Vec2F(cameraPoint.data[0] * config.mSize.data[0] / (float) videoMode.mWidth + xOffset,
                           cameraPoint.data[1] * config.mSize.data[1] / (float) videoMode.mHeight + yOffset);
    }
}

// Draw the current frame using OpenGL
//
// This method is called by QCAR when it wishes to render the current frame to
// the screen.
//
// *** QCAR will call this method periodically on a background thread ***
- (void)renderFrameQCAR
{
    [self setFramebuffer];
    NSString *targetNameString = nil;

    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Render video background and retrieve tracking state
    QCAR::State state = QCAR::Renderer::getInstance().begin();
    QCAR::Renderer::getInstance().drawVideoBackground();
    
    glEnable(GL_DEPTH_TEST);
    // We must detect if background reflection is active and adjust the culling direction.
    // If the reflection is active, this means the pose matrix has been reflected as well,
    // therefore standard counter clockwise face culling will result in "inside out" models.
    if (offTargetTrackingEnabled) {
        glDisable(GL_CULL_FACE);
    } else {
        glEnable(GL_CULL_FACE);
    }
    glCullFace(GL_BACK);
    if(QCAR::Renderer::getInstance().getVideoBackgroundConfig().mReflection == QCAR::VIDEO_BACKGROUND_REFLECTION_ON)
        glFrontFace(GL_CW);  //Front camera
    else
        glFrontFace(GL_CCW);   //Back camera

    for (int i = 0; i < state.getNumTrackableResults(); ++i) {
        // Get the trackable
        const QCAR::TrackableResult* result = state.getTrackableResult(i);
        const QCAR::Trackable& trackable = result->getTrackable();

        targetNameString = [NSString stringWithCString:trackable.getName() encoding:NSASCIIStringEncoding];
        NSLog(@"%@",targetNameString);
        //self.targetName.text = targetNameString;
        
        QCAR::Vec2F size = QCAR::Vec2F(247.0,173.0);
        /// Returns the current pose matrix in row-major order
        QCAR::Matrix34F pose = result->getPose();

        // Just use GLKit cause Vuforia makes things difficult
        QCAR::Matrix44F modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(pose);
        GLint viewport[4];
        viewport[0]=0.0f;
        viewport[1]=0.0f;
        viewport[2]=self.frame.size.width;
        viewport[3]=self.frame.size.height;
        GLKMatrix4 glkModelMatrix = GLKMatrix4Identity;
        
        GLKVector3 window_coord = GLKVector3Make(modelViewMatrix.data[12],
                                                 modelViewMatrix.data[13],
                                                 modelViewMatrix.data[14]);
        
        GLKMatrix4 projMatrix = GLKMatrix4MakeWithArray(vapp.projectionMatrix.data);
        
        GLKVector3 near_pt = GLKMathProject(window_coord, glkModelMatrix, projMatrix, viewport);
        CGPoint screenPoint = CGPointMake(near_pt.x, viewport[3]-near_pt.y);
        //[self emitAtPosition:point];
        NSLog(@"%f,%f",screenPoint.x,screenPoint.y);
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            if (!self.targetName.superview) {
                [self addSubview:self.targetName];
            }
            self.targetName.frame = CGRectMake(0,0,5,5);
            self.targetName.hidden = NO;
            self.targetName.center = screenPoint;
            [self emitAtPosition:screenPoint];
        });

        
    }
    if (0 == state.getNumTrackableResults()) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            self.targetName.hidden = YES;

        });
    }

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    QCAR::Renderer::getInstance().end();
    [self presentFramebuffer];
    
}



//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void)createFramebuffer
{
    if (context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    }
}


- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
    }
}


- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:context];
    }
    
    if (!defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
}


- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}

//QCAR::Vec2F cameraPointToScreenPoint(QCAR::Vec2F cameraPoint)
//{
//    QCAR::VideoMode videoMode = QCAR::CameraDevice::getInstance().getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
//    QCAR::VideoBackgroundConfig config = QCAR::Renderer::getInstance().getVideoBackgroundConfig();
//    
//    int xOffset = ((int) 320 - config.mSize.data[0]) / 2.0f + config.mPosition.data[0];
//    int yOffset = ((int) 480 - config.mSize.data[1]) / 2.0f - config.mPosition.data[1];
//    
//    if (YES)
//    {
//        // camera image is rotated 90 degrees
//        int rotatedX = videoMode.mHeight - cameraPoint.data[1];
//        int rotatedY = cameraPoint.data[0];
//        
//        return QCAR::Vec2F(rotatedX * config.mSize.data[0] / (float) videoMode.mHeight + xOffset,
//                           rotatedY * config.mSize.data[1] / (float) videoMode.mWidth + yOffset);
//    }
//    else
//    {
//        return QCAR::Vec2F(cameraPoint.data[0] * config.mSize.data[0] / (float) videoMode.mWidth + xOffset,
//                           cameraPoint.data[1] * config.mSize.data[1] / (float) videoMode.mHeight + yOffset);
//    }
//}


- (void)createEmmitter{
    
	CGRect viewBounds = self.layer.bounds;
	
	// Create the emitter layer
	self.emitterLayer = [CAEmitterLayer layer];
	
	// Cells spawn in a 50pt circle around the position
	self.emitterLayer.emitterPosition = CGPointMake(viewBounds.size.width/2.0, viewBounds.size.height/2.0);
	self.emitterLayer.emitterSize	= CGSizeMake(50, 0);
	self.emitterLayer.emitterMode	= kCAEmitterLayerOutline;
	self.emitterLayer.emitterShape	= kCAEmitterLayerCircle;
	self.emitterLayer.renderMode		= kCAEmitterLayerBackToFront;
    
    
    // Create the emitter Cell
	CAEmitterCell *emitterCell = [CAEmitterCell emitterCell];
	emitterCell.name = @"inbi";
    emitterCell.color = [[UIColor whiteColor] CGColor];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        emitterCell.contents = (id)[[UIImage imageNamed:@"InbiChipvFlip"] CGImage];
    }
    else{
        emitterCell.contents = (id)[[UIImage imageNamed:@"InbiChip"] CGImage];
    }
	emitterCell.scale = 1.00;
	emitterCell.scaleSpeed = 0.45;
	emitterCell.lifetime = 2.50;
	emitterCell.birthRate = 0.0;
	emitterCell.velocity = 275.00;
	
	// First traigles are emitted, which then spawn circles and star along their path
	self.emitterLayer.emitterCells = [NSArray arrayWithObject:emitterCell];
	[self.layer addSublayer:self.emitterLayer];
}

- (void)emitAtPosition:(CGPoint)position
{
	// Create Burst
	CABasicAnimation *burst = [CABasicAnimation animationWithKeyPath:@"emitterCells.inbi.birthRate"];
	burst.fromValue			= [NSNumber numberWithFloat: 75.0];
	burst.toValue			= [NSNumber numberWithFloat: 0.0];
	burst.duration			= 0.3;
	burst.timingFunction	= [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
	[self.emitterLayer addAnimation:burst forKey:@"burst"];
    
	// Move to position
	[CATransaction begin];
	[CATransaction setDisableActions: YES];
	self.emitterLayer.emitterPosition = position;
	[CATransaction commit];
}

@end
