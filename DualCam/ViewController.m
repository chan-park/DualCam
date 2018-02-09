//
//  ViewController.m
//  DualCam
//
//  Created by Chan Hee Park on 2/8/18.
//  Copyright © 2018 Fyusion. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#define ENABLE_DOUBLE_SHOT
@import Photos;
@interface ViewController () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDeviceDiscoverySession *discoverySession;

@property (nonatomic, strong) UIView *previewView;

@property (nonatomic, strong) AVCaptureDeviceInput *inputDevice;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;

@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) dispatch_queue_t dataQueue;

@property (nonatomic, strong) NSData *photoData;

@end

@implementation ViewController
{
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.captureSession = [[AVCaptureSession alloc]init];
    
    self.discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInTelephotoCamera]
                                                                                   mediaType:AVMediaTypeVideo
                                                                                    position:AVCaptureDevicePositionBack];
    
    /* Prepare preview */
    self.previewView = [[UIView alloc]initWithFrame:self.view.frame];
    [self.view addSubview:_previewView];
    AVCaptureVideoPreviewLayer *previewLayer = [[AVCaptureVideoPreviewLayer alloc]initWithSession:_captureSession];
    previewLayer.frame = self.previewView.frame;
    [self.previewView.layer addSublayer:previewLayer];
    
    /* prepare buttons */
    UIButton *takeButton = [[UIButton alloc]initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width/2 - 40, [UIScreen mainScreen].bounds.size.height - 150, 80, 80)];
    takeButton.backgroundColor = [UIColor redColor];
    [self.view addSubview:takeButton];
    [takeButton addTarget:self action:@selector(capturePhoto:) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *toggleButton = [[UIButton alloc]initWithFrame:CGRectMake(0, [UIScreen mainScreen].bounds.size.height - 150, 80, 80)];
    toggleButton.backgroundColor = [UIColor blueColor];
    [self.view addSubview:toggleButton];
    [toggleButton addTarget:self action:@selector(toggleCamera:) forControlEvents:UIControlEventTouchUpInside];
    
    self.sessionQueue = dispatch_queue_create("com.chanheepark.sessionQueue", DISPATCH_QUEUE_SERIAL);
    
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
    {
        case AVAuthorizationStatusAuthorized:
        {
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            dispatch_suspend(_sessionQueue);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted)
                    dispatch_resume(_sessionQueue);
                else
                    NSLog(@"%s, Access not granted.", __PRETTY_FUNCTION__);
            }];
            break;
        }
        default:
        {
            NSLog(@"%s, Access denied.", __PRETTY_FUNCTION__);
            break;
        }
    }

    dispatch_async(self.sessionQueue, ^{
        [self configureSession];
    });
    
}

- (void)viewWillAppear:(BOOL)animated
{
    dispatch_async(_sessionQueue, ^{
        [self.captureSession startRunning];
    });
}

- (void)configureSession
{
    [self.captureSession beginConfiguration];
    
    AVCaptureDeviceType preferedType = AVCaptureDeviceTypeBuiltInWideAngleCamera;
    self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    
    /* input */
    AVCaptureDeviceInput *inputCamera = [self makeDeviceInputWithDeviceType:preferedType];
    if (!inputCamera)
    {
        NSLog(@"input camera couldn't be created.");
        return;
    }
    
    if ([self.captureSession canAddInput:inputCamera])
    {
        [self.captureSession addInput:inputCamera];
        self.inputDevice = inputCamera;
    }
    else
    {
        NSLog(@"%s, cannot add telephoto input.", __PRETTY_FUNCTION__);
        [self.captureSession commitConfiguration];
        return;
    }
    
    /* output */
    AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc]init];
    if ([self.captureSession canAddOutput:photoOutput])
    {
        [self.captureSession addOutput:photoOutput];
        self.photoOutput = photoOutput;
        
        self.photoOutput.livePhotoCaptureEnabled = NO;
        self.photoOutput.depthDataDeliveryEnabled = NO;
        self.photoOutput.highResolutionCaptureEnabled = YES;
        
    }
    else
    {
        NSLog(@"%s, cannot add photo output.", __PRETTY_FUNCTION__);
        [self.captureSession commitConfiguration];
        return;
    }
    
    [self.captureSession commitConfiguration];
}

- (IBAction)capturePhoto:(id)sender
{
    dispatch_async(self.sessionQueue, ^{
        AVCapturePhotoSettings *photoSettings = [[AVCapturePhotoSettings alloc]init];
        photoSettings.highResolutionPhotoEnabled = YES;
        /* Call capturePhoto */
        [self.photoOutput capturePhotoWithSettings:photoSettings delegate:self];
    });
}

- (IBAction)toggleCamera:(id)sender
{
    if (!self.inputDevice)
    {
        NSLog(@"%s, no input device.", __PRETTY_FUNCTION__);
        return;
    }
    
    dispatch_async(_sessionQueue, ^{
        [self.captureSession removeInput:self.inputDevice];
        
        if (self.inputDevice.device.deviceType == AVCaptureDeviceTypeBuiltInWideAngleCamera)
        {
            AVCaptureDeviceInput *input = [self makeDeviceInputWithDeviceType:AVCaptureDeviceTypeBuiltInTelephotoCamera];
            if ([self.captureSession canAddInput:input])
            {
                self.inputDevice = input;
                [self.captureSession addInput:input];
            }
            else
            {
                NSLog(@"cannot add other device as input");
            }
        }
        
        if (self.inputDevice.device.deviceType == AVCaptureDeviceTypeBuiltInTelephotoCamera)
        {
            AVCaptureDeviceInput *input = [self makeDeviceInputWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera];
            if ([self.captureSession canAddInput:input])
            {
                self.inputDevice = input;
                [self.captureSession addInput:input];
            }
            else
            {
                NSLog(@"cannot add other device as input");
            }
        }
    });
}

#pragma mark - helpers
- (AVCaptureDeviceInput*)makeDeviceInputWithDeviceType:(AVCaptureDeviceType) deviceType
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:deviceType mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    NSError *error = nil;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                                  error:&error];
    if (!deviceInput)
    {
        NSLog(@"%s, cannot create device input. (%@)", __PRETTY_FUNCTION__, error);
        return nil;
    }
    return deviceInput;
}

#pragma mark - Capture Photo Delegates

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error
{
    if (error) {
        NSLog(@"%s, error: (%@)", __PRETTY_FUNCTION__, error);
        return;
    }
    
    self.photoData = [photo fileDataRepresentation];
    
}


- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings error:(NSError *)error
{
    if (error)
    {
        NSLog(@"%s, error: (%@)", __PRETTY_FUNCTION__, error);
        return;
    }
    if (!self.photoData)
    {
        NSLog(@"%s, no photo data to save.", __PRETTY_FUNCTION__);
        return;
    }
    
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized)
        {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
                PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
                [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.photoData options:options];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (!success)
                {
                    NSLog(@"Coudln't save photo to library");
                }
            }];
        }
        else
        {
            NSLog(@"PHPAuth fail.");
        }
    }];
    
}
@end
