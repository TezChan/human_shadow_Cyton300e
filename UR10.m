classdef UR10 < handle
    % Class for Cyton 300e robot simulation
    % This class was developed using a provided UR10 class of 
    % Peter Corke's Robotics Toolbox
    properties
        %> Robot Properties
        model;  %robot SerialLink Model
        workspace = [-1.5 0.5 -1 1 -0.4 1.5];   %specified Workspace
        CollisionFlag = 0;      %  flag that indicates if there is a collision
        taskExecutionFlag=0;    %  indicates the task stage of the robot
        toolModelFilename = []; % Available are: 'DabPrintNozzleTool.ply';        
        toolParametersFilename = []; % Available are: 'DabPrintNozzleToolParameters.mat';     
        
        %> properties of each brick
        Brick_h;
        b;
        b1;
        b2;
        b3;
        b4;
        brickVertexCount;
        brickVertexCount1;
        brickVertexCount2;
        brickVertexCount3;
        brickVertexCount4;
        BrickPose;
           
    end
    
    methods         
        %% Constructor that creates and plots the robot with an incorporated 3D model
        function self = UR10(toolModelAndTCPFilenames) 
            if 0 < nargin
                if length(toolModelAndTCPFilenames) ~= 2
                    error('Please pass a cell with two strings, toolModelFilename and toolCenterPointFilename');
                end
                self.toolModelFilename = toolModelAndTCPFilenames{1};
                self.toolParametersFilename = toolModelAndTCPFilenames{2};
            end

 [brick,a,VertexCount,Pose]=self.brickmove(0,-0.2,0.1);
 [brick1,a1,VertexCount1,Pose1]=self.brickmove(0.041,-0.2,0.1);
 [brick2,a2,VertexCount2,Pose2]=self.brickmove(-0.041,-0.2,0.1);
 
             self.Brick_h = [brick,brick1,brick2];
             self.b = a;
             self.b1 = a1;
             self.b2 = a2;
             
             self.brickVertexCount= VertexCount;
             self.brickVertexCount1 =VertexCount1;
             self.brickVertexCount2=VertexCount2;
              
             self.BrickPose= [Pose, Pose1,Pose2];          
             self.GetUR10Robot(); 
             self.PlotAndColourRobot();
        end

        %% GetUR10Robot
        % This Function creates a Cyton 300e Serial Link Model with
        % required DH Parameters
        function GetUR10Robot(self)
            pause(0.001);
            name = ['UR_10_',datestr(now,'yyyymmddTHHMMSSFFF')];
            base = [0 0 0];

    L1 = Link('d',0.062668,'a',0,'alpha',pi/2,'qlim',deg2rad([-360,360]));
    L2 = Link('d',0,'a',0,'alpha',-pi/2,'qlim', deg2rad([-110,110])); 
    L3 = Link('d',0.124096,'a',0,'alpha',pi/2,'qlim', deg2rad([-360,360]));
    L4 = Link('d',0,'a',0.065868,'alpha',-pi/2,'qlim',deg2rad([-20,170])); 
    L5 = Link('d',0,'a',0.065868,'alpha',pi/2,'qlim',deg2rad([-110,110]));
    L6 = Link('d',0,'a',0,'alpha',-pi/2,'qlim',deg2rad([-200,5]));
    L7 = Link('d',0.115545,'a',0,'alpha',0,'qlim',deg2rad([-360,360]));

            self.model = SerialLink([L1 L2 L3 L4 L5 L6 L7],'name',name);
            q = zeros(1,7);
            self.model.base = transl(base);
            
        end

        %% PlotAndColourRobot
        % Given a robot index, add the glyphs (vertices and faces) and
        % colour them in if data is available 
        function PlotAndColourRobot(self)%robot,workspace)
            for linkIndex = 0:self.model.n
                [ faceData, vertexData, plyData{linkIndex + 1} ] = plyread(['UR10Link',num2str(linkIndex),'.ply'],'tri'); %#ok<AGROW>
                self.model.faces{linkIndex + 1} = faceData;
                self.model.points{linkIndex + 1} = vertexData;
            end

            if ~isempty(self.toolModelFilename)
                [ faceData, vertexData, plyData{self.model.n + 1} ] = plyread(self.toolModelFilename,'tri'); 
                self.model.faces{self.model.n + 1} = faceData;
                self.model.points{self.model.n + 1} = vertexData;
                toolParameters = load(self.toolParametersFilename);
                self.model.tool = toolParameters.tool;
                self.model.qlim = toolParameters.qlim;
                warning('Please check the joint limits. They may be unsafe')
            end
            % Display robot
            self.model.plotopt = {'nojoints', 'noname','noarrow','nojaxes', 'nowrist','nobase', 'noraise','notiles'};
            self.model.plot3d(zeros(1,self.model.n),'noarrow','workspace',self.workspace);
            if isempty(findobj(get(gca,'Children'),'Type','Light'))
                camlight
            end  
            self.model.delay = 0;

            % Try to correctly colour the arm (if colours are in ply file data)
            for linkIndex = 0:self.model.n
                handles = findobj('Tag', self.model.name);
                h = get(handles,'UserData');
                try 
                    h.link(linkIndex+1).Children.FaceVertexCData = [plyData{linkIndex+1}.vertex.red ...
                                                                  , plyData{linkIndex+1}.vertex.green ...
                                                                  , plyData{linkIndex+1}.vertex.blue]/255;
                    h.link(linkIndex+1).Children.FaceColor = 'interp';
                catch ME_1
                    disp(ME_1);
                    continue;
                end
            end
            
            
        end
          
        %% RMRC 
        % BRIEF: This function calculates qMatrix for all joint angles to move
        % between Positions using Resolved Motion Rate Control(RMRC)
        % REFERENCE: This function is developed in reference to codes
        % provided in Lab9Solution_Question1.m 
        % DESCRIPTION:  qMatrix are calculated for each waypoints in the calculated
        % trajectory considering required joint velocity rate for all seven
        % joints. 
        
        function [qMatrix,steps]=RMRC(self, goalX, goalY, goalZ)            
t = 5;             % Total time (s)
deltaT = 0.10;      % Control frequency
steps = t/deltaT;   % No. of steps for simulation
delta = 2*pi/steps; % Small angle change
epsilon = 0.1;      % Threshold value for manipulability/Damped Least Squares
W = diag([1 1 1 0.1 0.1 0.1]);    % Weighting matrix for the velocity vector

% 1.2) Allocate array data
m = zeros(steps,1);             % Array for Measure of Manipulability
qMatrix = zeros(steps,7);       % Array for joint anglesR
qdot = zeros(steps,7);          % Array for joint velocities
theta = zeros(3,steps);         % Array for roll-pitch-yaw angles
x = zeros(3,steps);             % Array for x-y-z trajectory
positionError = zeros(3,steps); % For plotting trajectory error
angleError = zeros(3,steps);    % For plotting trajectory error
currentAngles = self.model.getpos();
currentPos  = self.model.fkine(currentAngles);



s = lspb(0,1,steps);                % Trapezoidal trajectory scalar
for i=1:steps
    x(1,i) = (1-s(i))*currentPos(1,4) + s(i)*goalX; % Points in x
    x(2,i) = (1-s(i))*currentPos(2,4) + s(i)*goalY; % Points in y
    x(3,i) = (1-s(i))*currentPos(3,4) + s(i)*goalZ; % Points in z
    theta(1,i) = 0;                 % Roll angle 
    theta(2,i) = 5*pi/9;            % Pitch angle
    theta(3,i) = 0;                 % Yaw angle
end


    

 T = [rpy2r(theta(1,1),theta(2,1),theta(3,1)) x(:,1);zeros(1,3) 1];          % Create transformation of first point and angle
  q0 = zeros(1,7);                                                            % Initial guess for joint angles
   qMatrix(1,:) = self.model.ikcon(T,q0);                                            % Solve joint angles to achieve first waypoint

% 1.4) Track the trajectory with RMRC
for i = 1:steps-1
    T = self.model.fkine(qMatrix(i,:));                                           % Get forward transformation at current joint state
    deltaX = x(:,i+1) - T(1:3,4);                                         	% Get position error from next waypoint
    Rd = rpy2r(theta(1,i+1),theta(2,i+1),theta(3,i+1));                     % Get next RPY angles, convert to rotation matrix
    Ra = T(1:3,1:3);                                                        % Current end-effector rotation matrix
    Rdot = (1/deltaT)*(Rd - Ra);                                                % Calculate rotation matrix error
    S = Rdot*Ra';                                                           % Skew symmetric!
    linear_velocity = (1/deltaT)*deltaX;
    angular_velocity = [S(3,2);S(1,3);S(2,1)];                              % Check the structure of Skew Symmetric matrix!!
    deltaTheta = tr2rpy(Rd*Ra');                                            % Convert rotation matrix to RPY angles
    xdot = W*[linear_velocity;angular_velocity];                          	% Calculate end-effector velocity to reach next waypoint.
    J = self.model.jacob0(qMatrix(i,:));                 % Get Jacobian at current joint state
    m(i) = sqrt(det(J*J'));
    if m(i) < epsilon  % If manipulability is less than given threshold
        lambda = (1 - m(i)/epsilon)*5E-2;
    else
        lambda = 0;
    end
    invJ = pinv(J'*J + lambda *eye(7))*J';                                   % DLS Inverse
    qdot(i,:) = (invJ*xdot)';                                                % Solve the RMRC equation (you may need to transpose the         vector)
    for j = 1:7                                                             % Loop through joints 1 to 7
        if qMatrix(i,j) + deltaT*qdot(i,j) < self.model.qlim(j,1)                     % If next joint angle is lower than joint limit...
            qdot(i,j) = 0; % Stop the motor
        elseif qMatrix(i,j) + deltaT*qdot(i,j) > self.model.qlim(j,2)                 % If next joint angle is greater than joint limit ...
            qdot(i,j) = 0; % Stop the motor
        end
    end
    qMatrix(i+1,:) = qMatrix(i,:) + deltaT*qdot(i,:);                         	% Update next joint state based on joint velocities
    positionError(:,i) = x(:,i+1) - T(1:3,4);                               % For plotting
    angleError(:,i) = deltaTheta;                                           % For plotting
    
            
end

end
        
 %% Move Brick
        % BRIEF: This function plots bricks with configurable positions
        % 
        % REFERENCE: CAD models were taken from http://done3d.com/concrete-column/
        %
        % DESCRIPTION:  This function takes position as input and plots a
        % brick in the environment which can be moved with the robot's
        % end-effector.
       
function [Brick_h,b,brickVertexCount,BrickPose]=brickmove(self,posx,posy,posz)
                  
        [f,b,data] = plyread('brick.ply','tri');
        vertexColours = [data.vertex.red, data.vertex.green, data.vertex.blue] / 255;
        Brick_h = trisurf(f,b(:,1) + posx,b(:,2) +posy, b(:,3) +posz ...
            ,'FaceVertexCData',vertexColours,'EdgeColor','interp','EdgeLighting','flat')
        
        brickVertexCount = size(b,1);
        BrickPose = eye(6);
        hold on; 

        
end

%% dropBrick
        % BRIEF: This function is used to animate the movement of the robot
        % carrying the brick from the brick stack to the wall .
        % 
        % DESCRIPTION:  This function takes position and the brick
        % properties as input and animates the movement of the end-effector
        % with an specified brick using a qMatrix provided by RMRC function
        % It also checks a possible collision while moving towards a goal 
        
function dropBrick(self,goalX,goalY,goalZ,brickNum,va,ba)
    [qMatrix,steps]= self.RMRC(goalX,goalY,goalZ);
    
   self.detectCollision(qMatrix);
    if(self.CollisionFlag == 0)  
        for c=1:steps
     self.model.plot(qMatrix(c,:),'trail','r-')
    currPos= self.model.fkine(qMatrix(c,:));
    self.BrickPose = makehgtform('translate',currPos(1:3,4)');
    updatedPoints = [self.BrickPose * [ba,ones(va,1)]']';
           self.Brick_h(1,brickNum).Vertices = updatedPoints(:,1:3);
           drawnow();   
        end
       
    else
       self.pickBrick(0.15,0,0.3);
    end 
end

%% pickBrick
        % BRIEF: This function is used to animate the movement of the robot
        % 
        % DESCRIPTION:  This function takes goal position as input and animates the movement 
        % of the end-effector using a qMatrix provided by RMRC function
        % It also checks a possible collision while moving towards a goal 
        
function pickBrick(self,goalX,goalY,goalZ)
    [qMatrix1,steps]= self.RMRC(goalX,goalY,goalZ);
   self.detectCollision(qMatrix1);
    if(self.CollisionFlag == 0)  
 
     self.model.plot(qMatrix1,'trail','r-')    
    else
       [qmatrix, steps]= self.RMRC(-0.1,0,0.25);
       self.model.plot(qmatrix,'trail','r-')   
    end 
end

%% detectCollision
        % BRIEF: This Function checks if the robot collides with any of the possible object 
        %in the environment that can obstruct robot movement 
        % 
        % REFERENCE: Functions used inside theese functions were taken from
        % tutorial solutions. 
        %
        % DESCRIPTION:  This function is used to to plot rectangular Prism on the
        % possible objects that it can collide with and checks if the robot
        % will be colliding to any of them while moving in the 
        % planned trajectory.
        
function detectCollision(self,qMatrix)
           plotOptions.plotFaces = false;
% RectangularPrism()function was used from the provided script in Lab 5 
[vertex,faces,faceNormals] = RectangularPrism([0.25,-0.33,-0.39], [0.29,0.31,0.07],plotOptions); 
[vertex1,faces1,faceNormals1] = RectangularPrism([0.25,0.08,0.07], [0.29,0.31,0.15],plotOptions);
[vertex2,faces2,faceNormals2] = RectangularPrism([-0.15,0.15,-0.4], [0.15,-0.38,-0.08],plotOptions);
[vertex3,faces3,faceNormals3] = RectangularPrism([-0.06,-0.12,-0.09], [0.06,-0.265,0.065],plotOptions);
axis equal
camlight

wall_1= IsCollision(self.model,qMatrix,faces,vertex,faceNormals);
wall_2= IsCollision(self.model,qMatrix,faces1,vertex1,faceNormals1);
wall_3= IsCollision(self.model,qMatrix,faces2,vertex2,faceNormals2);
wall_4= IsCollision(self.model,qMatrix,faces3,vertex3,faceNormals3);

if wall_1==true || wall_2 == true || wall_3 == true || wall_4 == true
self.CollisionFlag =1;
disp('avoiding collision')

end

 
end
 %% IsIntersectionPointInsideTriangle               [ Taken From: Lab5 Solutions]
% Given a point which is known to be on the same plane as the triangle
% determine if the point is 
% inside (result == 1) or 
% outside a triangle (result ==0 )
function result = IsIntersectionPointInsideTriangle(self,intersectP,triangleVerts)

u = triangleVerts(2,:) - triangleVerts(1,:);
v = triangleVerts(3,:) - triangleVerts(1,:);

uu = dot(u,u);
uv = dot(u,v);
vv = dot(v,v);

w = intersectP - triangleVerts(1,:);
wu = dot(w,u);
wv = dot(w,v);

D = uv * uv - uu * vv;

% Get and test parametric coords (s and t)
s = (uv * wv - vv * wu) / D;
if (s < 0.0 || s > 1.0)        % intersectP is outside Triangle
    result = 0;
    return;
end

t = (uv * wu - uu * wv) / D;
if (t < 0.0 || (s + t) > 1.0)  % intersectP is outside Triangle
    result = 0;
    return;
end

result = 1;                      % intersectP is in Triangle
end

%% IsCollision                  [ Taken From: Lab5 Solutions]
% This is based upon the output of questions 2.5 and 2.6
% Given a robot model (robot), and trajectory (i.e. joint state vector) (qMatrix)
% and triangle obstacles in the environment (faces,vertex,faceNormals)
function result = IsCollision(self,qMatrix,faces,vertex,faceNormals,returnOnceFound)
if nargin < 6
    returnOnceFound = true;
end
result = false;

for qIndex = 1:size(qMatrix,1)
    % Get the transform of every joint (i.e. start and end of every link)
    tr = GetLinkPoses(qMatrix(qIndex,:), self);

    % Go through each link and also each triangle face
    for i = 1 : size(tr,3)-1    
        for faceIndex = 1:size(faces,1)
            vertOnPlane = vertex(faces(faceIndex,1)',:);
            [intersectP,check] = LinePlaneIntersection(faceNormals(faceIndex,:),vertOnPlane,tr(1:3,4,i)',tr(1:3,4,i+1)'); 
            if check == 1 && IsIntersectionPointInsideTriangle(intersectP,vertex(faces(faceIndex,:)',:))
                plot3(intersectP(1),intersectP(2),intersectP(3),'g*');
                display('Intersection');
                result = true;
                if returnOnceFound
                    return
                end
            end
        end    
    end
end
end

%% GetLinkPoses                     [ Taken From: Lab5 Solutions]
% q - robot joint angles
% robot -  seriallink robot model
% transforms - list of transforms
function [ transforms ] = GetLinkPoses( q, self)

links = self.links;
transforms = zeros(4, 4, length(links) + 1);
transforms(:,:,1) = self.base;

for i = 1:length(links)
    L = links(1,i);
    
    current_transform = transforms(:,:, i);
    
    current_transform = current_transform * trotz(q(1,i) + L.offset) * ...
    transl(0,0, L.d) * transl(L.a,0,0) * trotx(L.alpha);
    transforms(:,:,i + 1) = current_transform;
end
end

%% Functions to pick and drop individual bricks
function pickBrick1(self)
  
    self.pickBrick(0,-0.2,0.1);
   
   self.taskExecutionFlag = 1
    
end
function DropBrick1(self)
   self.dropBrick(0.2,0,0.25,1,self.brickVertexCount,self.b);
   self.dropBrick(0.27,0.05,0.09,1,self.brickVertexCount,self.b);
   self.pickBrick(0.2,0,0.25);
   self.taskExecutionFlag = 2;
end
function pickBrick2(self)
  
    self.pickBrick(0.041,-0.2,0.1);
   
     self.taskExecutionFlag = 3;
    
end

function DropBrick2(self)
   self.dropBrick(0.2,0,0.25,2,self.brickVertexCount1,self.b1);
   self.dropBrick(0.27,-0.04,0.09,2,self.brickVertexCount1,self.b1);
   self.pickBrick(0.2,0,0.25);
   self.taskExecutionFlag = 4;
   
end

function pickBrick3(self)
  
    
    self.pickBrick(-0.041,-0.2,0.1);
   
     self.taskExecutionFlag = 5;
    
end

function DropBrick3(self)
   self.dropBrick(0.1,-0.2,0.3,3,self.brickVertexCount2,self.b2);
   self.dropBrick(0.25,-0.09,0.085,3,self.brickVertexCount2,self.b2);
   self.pickBrick(0.2,0,0.25);
   self.taskExecutionFlag = 6;
   
end

    end
end
