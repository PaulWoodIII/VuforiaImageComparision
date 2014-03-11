//
//  WIViewController.m
//  VuforiaTargets
//
//  Created by Paul Wood on 2/21/14.
//  Copyright (c) 2014 Walkin. All rights reserved.
//

#import "WIViewController.h"
#import "ImageTargetsViewController.h"
#import "WIImageTarget.h"

@interface WIViewController ()

@end

@implementation WIViewController

- (id)init{
    self = [super initWithNibName:@"WIViewController" bundle:nil];
    if (self) {
        [self loadTargets];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self addStartButton];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)addStartButton{
    UIBarButtonItem *startButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Start", @"Start")
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(startWithSelectedTargets)];
    self.navigationItem.rightBarButtonItem = startButton;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)startWithSelectedTargets{
    ImageTargetsViewController *vc = [[ImageTargetsViewController alloc] init];
    vc.imageTargets = self.imageTargets;
    [self.navigationController pushViewController:vc animated:NO];
}

- (void)loadTargets{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"targets" ofType:@"json"];
    NSData *data = [fm contentsAtPath:bundlePath];
    NSError *error;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        return;
    }
    else{
        NSMutableArray *array = [dict objectForKey:@"targets"];
        self.imageTargets = [[NSMutableArray alloc] initWithCapacity:array.count];
        for (NSDictionary *dict in array){
            WIImageTarget *target = [WIImageTarget imageTargetWithDictionary:dict];
            [self.imageTargets addObject:target];
        }
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView 
didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    WIImageTarget *target = [self.imageTargets objectAtIndex:indexPath.row];
    if ([target isSelected]) {
        target.isSelected = NO;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    else {
        target.isSelected = YES;
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    [cell setSelected:NO];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    return self.imageTargets.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    cell = [tableView dequeueReusableCellWithIdentifier:kWITargetTableViewCellReuseIdentifier];
    
    if (!cell) {
        cell = [[WITargetTableViewCell alloc] init];
    }

    [self configureCell:cell forRowAtIndexPath:indexPath];

    return cell;
}

- (void)configureCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath
{
    WITargetTableViewCell *targetCell = (WITargetTableViewCell *)cell;
    WIImageTarget *target = [self.imageTargets objectAtIndex:indexPath.row];

    targetCell.targetName.text = target.imageString;
    targetCell.targetStarRating.text = @"";
    [targetCell.mainImage setImage:[target image]];
    [targetCell.featureImage setImage:[target featureImage]];
    
    if ([target isSelected]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
}

@end

@implementation WITargetTableViewCell

NSString *const kWITargetTableViewCellReuseIdentifier = @"WITargetTableViewCell";

- (id)init
{
	if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WITargetTableViewCell"])
	{
        self.contentArray = [[NSBundle mainBundle] loadNibNamed:@"WITargetTableViewCell"
                                                          owner:self
                                                        options:nil];
        self.backgroundColor = [UIColor clearColor];
        [self addSubview:self.content];
	}
	return self;
}

@end
